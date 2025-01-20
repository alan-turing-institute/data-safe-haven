"""Pulumi component for SRE backup"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions

from data_safe_haven.infrastructure.components import LinuxVMComponentProps, VMComponent
from data_safe_haven.functions import b64encode, replace_separators


class SREBackupProps:
    """Properties for SREBackupComponent"""

    def __init__(
        self,
        location: Input[str],
        resource_group_name: Input[str],
        storage_account_data_private_sensitive_id: Input[str],
        storage_account_data_private_sensitive_name: Input[str],
        subnet_backup_name: Input[str]
    ) -> None:
        self.location = location
        self.resource_group_name = resource_group_name
        self.storage_account_data_private_sensitive_id = (
            storage_account_data_private_sensitive_id
        )
        self.storage_account_data_private_sensitive_name = (
            storage_account_data_private_sensitive_name
        )
        self.subnet_backup_name = subnet_backup_name


class SREBackupComponent(ComponentResource):
    """Deploy SRE backup with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREBackupProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:BackupComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "backup"} | (tags if tags else {})

        # Template cloud init
        cloudinit = Output.all(
            apt_proxy_server_hostname=props.apt_proxy_server_hostname,
            storage_account_desired_state_name=props.storage_account_desired_state_name,
            storage_account_data_private_user_name=props.storage_account_data_private_user_name,
            storage_account_data_private_sensitive_name=props.storage_account_data_private_sensitive_name,
        ).apply(lambda kwargs: self.template_cloudinit(**kwargs))

        # Backup virtual machine
        VMComponent(
            replace_separators(f"{self._name}_vm_backup", "_"),
            LinuxVMComponentProps(
                admin_password=props.admin_password,
                admin_username=props.admin_username,
                b64cloudinit=cloudinit.apply(b64encode),
                data_collection_rule_id=props.data_collection_rule_id,
                data_collection_endpoint_id=props.data_collection_endpoint_id,
                ip_address_private=...,
                location=props.location,
                maintenance_configuration_id=props.maintenance_configuration_id,
                resource_group_name=props.resource_group_name,
                subnet_name=props.subnet_backup_name,
                virtual_network_name=props.virtual_network_name,
                virtual_network_resource_group_name=props.resource_group_name,
                vm_name=Output.concat(
                    stack_name, "-vm-backup"
                ).apply(lambda s: replace_separators(s, "-")),
                vm_size="Standard_B2s_v2",
            ),
            opts=child_opts,
            tags=child_tags,
        )
