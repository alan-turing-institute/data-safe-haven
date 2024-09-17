"""Pulumi component for SRE desired state"""

from collections.abc import Mapping, Sequence

import yaml
from pulumi import (
    ComponentResource,
    FileAsset,
    Input,
    Output,
    ResourceOptions,
    StringAsset,
)
from pulumi_azure_native import (
    network,
    resources,
    storage,
)

from data_safe_haven.functions import (
    alphanumeric,
    replace_separators,
    sha256hash,
    truncate_tokens,
)
from data_safe_haven.infrastructure.common import (
    get_id_from_rg,
    get_id_from_subnet,
    get_name_from_rg,
)
from data_safe_haven.infrastructure.components import (
    BlobContainerAcl,
    BlobContainerAclProps,
    NFSV3StorageAccount,
)
from data_safe_haven.resources import resources_path
from data_safe_haven.types import AzureDnsZoneNames


class SREDesiredStateProps:
    """Properties for SREDesiredStateComponent"""

    def __init__(
        self,
        admin_ip_addresses: Input[Sequence[str]],
        dns_private_zones: Input[dict[str, network.PrivateZone]],
        gitea_hostname: Input[str],
        hedgedoc_hostname: Input[str],
        location: Input[str],
        resource_group: Input[resources.ResourceGroup],
        subscription_name: Input[str],
        subnet_desired_state: Input[network.GetSubnetResult],
    ) -> None:
        self.admin_ip_addresses = admin_ip_addresses
        self.dns_private_zones = dns_private_zones
        self.gitea_hostname = gitea_hostname
        self.hedgedoc_hostname = hedgedoc_hostname
        self.location = location
        self.resource_group_id = Output.from_input(resource_group).apply(get_id_from_rg)
        self.resource_group_name = Output.from_input(resource_group).apply(
            get_name_from_rg
        )
        self.subnet_desired_state_id = Output.from_input(subnet_desired_state).apply(
            get_id_from_subnet
        )
        self.subscription_name = subscription_name


class SREDesiredStateComponent(ComponentResource):
    """Deploy SRE desired state with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREDesiredStateProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:DesiredStateComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "data"} | (tags if tags else {})

        # Deploy desired state storage account
        # - This holds the /desired_state container that is mounted by workspaces
        # - Azure blobs have worse NFS support but can be accessed with Azure Storage Explorer
        storage_account = NFSV3StorageAccount(
            f"{self._name}_storage_account",
            account_name=alphanumeric(
                f"{''.join(truncate_tokens(stack_name.split('-'), 11))}desiredstate{sha256hash(self._name)}"
            )[:24],
            allowed_ip_addresses=props.admin_ip_addresses,
            location=props.location,
            resource_group_name=props.resource_group_name,
            subnet_id=props.subnet_desired_state_id,
            opts=child_opts,
            tags=child_tags,
        )
        # Deploy desired state share
        container_desired_state = storage.BlobContainer(
            f"{self._name}_blob_desired_state",
            account_name=storage_account.name,
            container_name="desiredstate",
            default_encryption_scope="$account-encryption-key",
            deny_encryption_scope_override=False,
            public_access=storage.PublicAccess.NONE,
            resource_group_name=props.resource_group_name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=storage_account),
            ),
        )
        # Set storage container ACLs
        BlobContainerAcl(
            f"{container_desired_state._name}_acl",
            BlobContainerAclProps(
                acl_user="r-x",
                acl_group="r-x",
                acl_other="r-x",
                # ensure that the above permissions are also set on any newly created
                # files (eg. with Azure Storage Explorer)
                apply_default_permissions=True,
                container_name=container_desired_state.name,
                resource_group_name=props.resource_group_name,
                storage_account_name=storage_account.name,
                subscription_name=props.subscription_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=container_desired_state)
            ),
        )
        # Create file assets to upload
        desired_state_directory = (resources_path / "workspace" / "ansible").absolute()
        files_desired_state = [
            (
                FileAsset(str(file_path)),
                file_path.name,
                str(file_path.relative_to(desired_state_directory)),
            )
            for file_path in sorted(desired_state_directory.rglob("*"))
            if file_path.is_file() and not file_path.name.startswith(".")
        ]
        # Upload file assets to desired state container
        for file_asset, file_name, file_path in files_desired_state:
            storage.Blob(
                f"{container_desired_state._name}_blob_{file_name}",
                account_name=storage_account.name,
                blob_name=file_path,
                container_name=container_desired_state.name,
                resource_group_name=props.resource_group_name,
                source=file_asset,
            )
        # Upload ansible vars file
        storage.Blob(
            f"{container_desired_state._name}_blob_pulumi_vars",
            account_name=storage_account.name,
            blob_name="vars/pulumi_vars.yaml",
            container_name=container_desired_state.name,
            resource_group_name=props.resource_group_name,
            source=Output.all(
                gitea_hostname=props.gitea_hostname,
                hedgedoc_hostname=props.hedgedoc_hostname,
            ).apply(lambda kwargs: StringAsset(self.ansible_vars_file(**kwargs))),
        )
        # Set up a private endpoint for the desired state storage account
        storage_account_endpoint = network.PrivateEndpoint(
            f"{storage_account._name}_private_endpoint",
            location=props.location,
            private_endpoint_name=f"{stack_name}-pep-storage-account-desired-state",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["blob"],
                    name=f"{stack_name}-cnxn-pep-storage-account-desired-state",
                    private_link_service_id=storage_account.id,
                )
            ],
            resource_group_name=props.resource_group_name,
            subnet=network.SubnetArgs(id=props.subnet_desired_state_id),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=["custom_dns_configs"],
                    parent=storage_account,
                ),
            ),
            tags=child_tags,
        )
        # Add a private DNS record for each desired state endpoint custom DNS config
        network.PrivateDnsZoneGroup(
            f"{storage_account._name}_private_dns_zone_group",
            private_dns_zone_configs=[
                network.PrivateDnsZoneConfigArgs(
                    name=replace_separators(
                        f"{stack_name}-storage-account-desired-state-to-{dns_zone_name}",
                        "-",
                    ),
                    private_dns_zone_id=props.dns_private_zones[dns_zone_name].id,
                )
                for dns_zone_name in AzureDnsZoneNames.STORAGE_ACCOUNT
            ],
            private_dns_zone_group_name=f"{stack_name}-dzg-storage-account-desired-state",
            private_endpoint_name=storage_account_endpoint.name,
            resource_group_name=props.resource_group_name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=storage_account),
            ),
        )

        self.storage_account_name = storage_account.name

    @staticmethod
    def ansible_vars_file(**kwargs: str) -> str:
        return yaml.safe_dump(kwargs, explicit_start=True, indent=2)
