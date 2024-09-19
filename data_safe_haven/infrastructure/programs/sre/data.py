"""Pulumi component for SRE data"""

from collections.abc import Mapping, Sequence
from typing import ClassVar

import pulumi_random
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import (
    authorization,
    keyvault,
    managedidentity,
    network,
    resources,
    storage,
)

from data_safe_haven.external import AzureIPv4Range
from data_safe_haven.functions import (
    alphanumeric,
    get_key_vault_name,
    replace_separators,
    seeded_uuid,
    sha256hash,
    truncate_tokens,
)
from data_safe_haven.infrastructure.common import (
    get_id_from_rg,
    get_id_from_subnet,
    get_name_from_rg,
)
from data_safe_haven.infrastructure.components import (
    NFSV3BlobContainerComponent,
    NFSV3BlobContainerProps,
    SSLCertificate,
    SSLCertificateProps,
    WrappedNFSV3StorageAccount,
)
from data_safe_haven.types import AzureDnsZoneNames


class SREDataProps:
    """Properties for SREDataComponent"""

    def __init__(
        self,
        admin_email_address: Input[str],
        admin_group_id: Input[str],
        admin_ip_addresses: Input[Sequence[str]],
        data_provider_ip_addresses: Input[Sequence[str]],
        dns_private_zones: Input[dict[str, network.PrivateZone]],
        dns_record: Input[network.RecordSet],
        dns_server_admin_password: Input[pulumi_random.RandomPassword],
        location: Input[str],
        resource_group: Input[resources.ResourceGroup],
        sre_fqdn: Input[str],
        storage_quota_gb_home: Input[int],
        storage_quota_gb_shared: Input[int],
        subnet_data_configuration: Input[network.GetSubnetResult],
        subnet_data_private: Input[network.GetSubnetResult],
        subscription_id: Input[str],
        subscription_name: Input[str],
        tenant_id: Input[str],
    ) -> None:
        self.admin_email_address = admin_email_address
        self.admin_group_id = admin_group_id
        self.data_configuration_ip_addresses = admin_ip_addresses
        self.data_private_sensitive_ip_addresses = Output.all(
            admin_ip_addresses, data_provider_ip_addresses
        ).apply(
            lambda address_lists: {
                ip for address_list in address_lists for ip in address_list
            }
        )
        self.dns_private_zones = dns_private_zones
        self.dns_record = dns_record
        self.password_dns_server_admin = dns_server_admin_password
        self.location = location
        self.resource_group_id = Output.from_input(resource_group).apply(get_id_from_rg)
        self.resource_group_name = Output.from_input(resource_group).apply(
            get_name_from_rg
        )
        self.sre_fqdn = sre_fqdn
        self.storage_quota_gb_home = storage_quota_gb_home
        self.storage_quota_gb_shared = storage_quota_gb_shared
        self.subnet_data_configuration_id = Output.from_input(
            subnet_data_configuration
        ).apply(get_id_from_subnet)
        self.subnet_data_private_id = Output.from_input(subnet_data_private).apply(
            get_id_from_subnet
        )
        self.subscription_id = subscription_id
        self.subscription_name = subscription_name
        self.tenant_id = tenant_id


class SREDataComponent(ComponentResource):
    """Deploy SRE data with Pulumi"""

    azure_role_ids: ClassVar[dict[str, str]] = {
        "Storage Blob Data Owner": "b7e6dc6d-f1e8-4753-8033-0f276bb0955b"
    }

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREDataProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:DataComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "data"} | (tags if tags else {})

        # Define Key Vault reader
        identity_key_vault_reader = managedidentity.UserAssignedIdentity(
            f"{self._name}_id_key_vault_reader",
            location=props.location,
            resource_group_name=props.resource_group_name,
            resource_name_=f"{stack_name}-id-key-vault-reader",
            opts=child_opts,
            tags=child_tags,
        )

        # Define SRE KeyVault
        key_vault = keyvault.Vault(
            f"{self._name}_kv_secrets",
            location=props.location,
            properties=keyvault.VaultPropertiesArgs(
                access_policies=[
                    keyvault.AccessPolicyEntryArgs(
                        object_id=props.admin_group_id,
                        permissions=keyvault.PermissionsArgs(
                            certificates=[
                                "get",
                                "list",
                                "delete",
                                "create",
                                "import",
                                "update",
                                "managecontacts",
                                "getissuers",
                                "listissuers",
                                "setissuers",
                                "deleteissuers",
                                "manageissuers",
                                "recover",
                                "purge",
                            ],
                            keys=[
                                "encrypt",
                                "decrypt",
                                "sign",
                                "verify",
                                "get",
                                "list",
                                "create",
                                "update",
                                "import",
                                "delete",
                                "backup",
                                "restore",
                                "recover",
                                "purge",
                            ],
                            secrets=[
                                "get",
                                "list",
                                "set",
                                "delete",
                                "backup",
                                "restore",
                                "recover",
                                "purge",
                            ],
                        ),
                        tenant_id=props.tenant_id,
                    ),
                    keyvault.AccessPolicyEntryArgs(
                        object_id=identity_key_vault_reader.principal_id,
                        permissions=keyvault.PermissionsArgs(
                            certificates=[
                                "get",
                                "list",
                            ],
                            keys=[
                                "get",
                                "list",
                            ],
                            secrets=[
                                "get",
                                "list",
                            ],
                        ),
                        tenant_id=props.tenant_id,
                    ),
                ],
                enabled_for_deployment=True,
                enabled_for_disk_encryption=True,
                enabled_for_template_deployment=True,
                sku=keyvault.SkuArgs(
                    family="A",
                    name=keyvault.SkuName.STANDARD,
                ),
                soft_delete_retention_in_days=7,  # minimum allowed
                tenant_id=props.tenant_id,
            ),
            resource_group_name=props.resource_group_name,
            vault_name=get_key_vault_name(stack_name)[:24],  # maximum of 24 characters
            opts=child_opts,
            tags=child_tags,
        )

        # Define SSL certificate for this FQDN
        sre_fqdn_certificate = SSLCertificate(
            f"{self._name}_kvc_https_certificate",
            SSLCertificateProps(
                certificate_secret_name=Output.from_input(props.sre_fqdn).apply(
                    lambda s: replace_separators(s, "-")
                ),
                domain_name=props.sre_fqdn,
                admin_email_address=props.admin_email_address,
                key_vault_name=key_vault.name,
                networking_resource_group_name=props.resource_group_name,
                subscription_name=props.subscription_name,
            ),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    depends_on=[props.dns_record],
                    parent=key_vault,
                ),  # we need the delegation NS record to exist before generating the certificate
            ),
        )

        # Secret: database service admin password
        password_database_service_admin = pulumi_random.RandomPassword(
            f"{self._name}_password_database_service_admin",
            length=20,
            special=True,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=key_vault)),
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_database_service_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=password_database_service_admin.result,
            ),
            resource_group_name=props.resource_group_name,
            secret_name="password-database-service-admin",
            vault_name=key_vault.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=password_database_service_admin)
            ),
            tags=child_tags,
        )

        # Secret: DNS server admin password
        keyvault.Secret(
            f"{self._name}_kvs_password_dns_server_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=props.password_dns_server_admin.result,
            ),
            resource_group_name=props.resource_group_name,
            secret_name="password-dns-server-admin",
            vault_name=key_vault.name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=key_vault)),
            tags=child_tags,
        )

        # Secret: Gitea database admin password
        password_gitea_database_admin = pulumi_random.RandomPassword(
            f"{self._name}_password_gitea_database_admin",
            length=20,
            special=True,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=key_vault)),
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_gitea_database_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=password_gitea_database_admin.result
            ),
            resource_group_name=props.resource_group_name,
            secret_name="password-gitea-database-admin",
            vault_name=key_vault.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=password_gitea_database_admin)
            ),
            tags=child_tags,
        )

        # Secret: Hedgedoc database admin password
        password_hedgedoc_database_admin = pulumi_random.RandomPassword(
            f"{self._name}_password_hedgedoc_database_admin",
            length=20,
            special=True,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=key_vault)),
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_hedgedoc_database_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=password_hedgedoc_database_admin.result
            ),
            resource_group_name=props.resource_group_name,
            secret_name="password-hedgedoc-database-admin",
            vault_name=key_vault.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=password_hedgedoc_database_admin)
            ),
            tags=child_tags,
        )

        # Secret: Nexus admin password
        password_nexus_admin = pulumi_random.RandomPassword(
            f"{self._name}_password_nexus_admin",
            length=20,
            special=True,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=key_vault)),
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_nexus_admin",
            properties=keyvault.SecretPropertiesArgs(value=password_nexus_admin.result),
            resource_group_name=props.resource_group_name,
            secret_name="password-nexus-admin",
            vault_name=key_vault.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=password_nexus_admin)
            ),
            tags=child_tags,
        )

        # Secret: Guacamole user database admin password
        password_user_database_admin = pulumi_random.RandomPassword(
            f"{self._name}_password_user_database_admin",
            length=20,
            special=True,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=key_vault)),
        )
        kvs_password_user_database_admin = keyvault.Secret(
            f"{self._name}_kvs_password_user_database_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=password_user_database_admin.result
            ),
            resource_group_name=props.resource_group_name,
            secret_name="password-user-database-admin",
            vault_name=key_vault.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=password_user_database_admin)
            ),
            tags=child_tags,
        )

        # Secret: Workspace admin password
        password_workspace_admin = pulumi_random.RandomPassword(
            f"{self._name}_password_workspace_admin",
            length=20,
            special=True,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=key_vault)),
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_workspace_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=password_workspace_admin.result
            ),
            resource_group_name=props.resource_group_name,
            secret_name="password-workspace-admin",
            vault_name=key_vault.name,
            opts=ResourceOptions(parent=password_workspace_admin),
            tags=child_tags,
        )

        # Deploy configuration data storage account
        # - This holds file shares that are mounted by Azure Container Instances
        storage_account_data_configuration = storage.StorageAccount(
            f"{self._name}_storage_account_data_configuration",
            # Note that account names have a maximum of 24 characters
            account_name=alphanumeric(
                f"{''.join(truncate_tokens(stack_name.split('-'), 14))}configdata"
            )[:24],
            kind=storage.Kind.STORAGE_V2,
            large_file_shares_state=storage.LargeFileSharesState.DISABLED,
            location=props.location,
            minimum_tls_version=storage.MinimumTlsVersion.TLS1_2,
            network_rule_set=storage.NetworkRuleSetArgs(
                bypass=storage.Bypass.AZURE_SERVICES,
                default_action=storage.DefaultAction.DENY,
                ip_rules=Output.from_input(props.data_configuration_ip_addresses).apply(
                    lambda ip_ranges: [
                        storage.IPRuleArgs(
                            action=storage.Action.ALLOW,
                            i_p_address_or_range=str(ip_address),
                        )
                        for ip_range in sorted(ip_ranges)
                        for ip_address in AzureIPv4Range.from_cidr(ip_range).all_ips()
                    ]
                ),
                virtual_network_rules=[
                    storage.VirtualNetworkRuleArgs(
                        virtual_network_resource_id=props.subnet_data_configuration_id,
                    )
                ],
            ),
            resource_group_name=props.resource_group_name,
            sku=storage.SkuArgs(name=storage.SkuName.STANDARD_LRS),
            opts=child_opts,
            tags=child_tags,
        )
        # Retrieve configuration data storage account keys
        storage_account_data_configuration_keys = Output.all(
            account_name=storage_account_data_configuration.name,
            resource_group_name=props.resource_group_name,
        ).apply(
            lambda kwargs: storage.list_storage_account_keys(
                account_name=kwargs["account_name"],
                resource_group_name=kwargs["resource_group_name"],
            )
        )
        # Set up a private endpoint for the configuration data storage account
        storage_account_data_configuration_private_endpoint = network.PrivateEndpoint(
            f"{storage_account_data_configuration._name}_private_endpoint",
            location=props.location,
            private_endpoint_name=f"{stack_name}-pep-storage-account-data-configuration",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["file"],
                    name=f"{stack_name}-cnxn-pep-storage-account-data-configuration",
                    private_link_service_id=storage_account_data_configuration.id,
                )
            ],
            resource_group_name=props.resource_group_name,
            subnet=network.SubnetArgs(id=props.subnet_data_configuration_id),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=["custom_dns_configs"],
                    parent=storage_account_data_configuration,
                ),
            ),
            tags=child_tags,
        )
        # Add a private DNS record for each configuration data endpoint custom DNS config
        network.PrivateDnsZoneGroup(
            f"{storage_account_data_configuration._name}_private_dns_zone_group",
            private_dns_zone_configs=[
                network.PrivateDnsZoneConfigArgs(
                    name=replace_separators(
                        f"{stack_name}-storage-account-data-configuration-to-{dns_zone_name}",
                        "-",
                    ),
                    private_dns_zone_id=props.dns_private_zones[dns_zone_name].id,
                )
                for dns_zone_name in AzureDnsZoneNames.STORAGE_ACCOUNT
            ],
            private_dns_zone_group_name=f"{stack_name}-dzg-storage-account-data-configuration",
            private_endpoint_name=storage_account_data_configuration_private_endpoint.name,
            resource_group_name=props.resource_group_name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=storage_account_data_configuration)
            ),
        )
        # Deploy sensitive data blob storage account
        # - This holds the /mnt/input and /mnt/output containers that are mounted by workspaces
        # - Azure blobs have worse NFS support but can be accessed with Azure Storage Explorer
        storage_account_data_private_sensitive = WrappedNFSV3StorageAccount(
            f"{self._name}_storage_account_data_private_sensitive",
            # Storage account names have a maximum of 24 characters
            account_name=alphanumeric(
                f"{''.join(truncate_tokens(stack_name.split('-'), 11))}sensitivedata{sha256hash(self._name)}"
            )[:24],
            allowed_ip_addresses=props.data_private_sensitive_ip_addresses,
            location=props.location,
            subnet_id=props.subnet_data_private_id,
            resource_group_name=props.resource_group_name,
            opts=child_opts,
            tags=child_tags,
        )
        # Deploy storage containers
        NFSV3BlobContainerComponent(
            f"{self._name}_blob_egress",
            NFSV3BlobContainerProps(
                acl_user="rwx",
                acl_group="rwx",
                acl_other="rwx",
                # due to an Azure bug `apply_default_permissions=True` also gives user
                # 65533 ownership of the fileshare (preventing use inside the SRE)
                apply_default_permissions=False,
                container_name="egress",
                resource_group_name=props.resource_group_name,
                storage_account=storage_account_data_private_sensitive,
                subscription_name=props.subscription_name,
            ),
        )
        NFSV3BlobContainerComponent(
            f"{self._name}_blob_ingress",
            NFSV3BlobContainerProps(
                acl_user="rwx",
                acl_group="r-x",
                acl_other="r-x",
                # ensure that the above permissions are also set on any newly created
                # files (eg. with Azure Storage Explorer)
                apply_default_permissions=True,
                container_name="ingress",
                resource_group_name=props.resource_group_name,
                storage_account=storage_account_data_private_sensitive,
                subscription_name=props.subscription_name,
            ),
        )
        # Set up a private endpoint for the sensitive data storage account
        storage_account_data_private_sensitive_endpoint = network.PrivateEndpoint(
            f"{storage_account_data_private_sensitive._name}_private_endpoint",
            location=props.location,
            private_endpoint_name=f"{stack_name}-pep-storage-account-data-private-sensitive",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["blob"],
                    name=f"{stack_name}-cnxn-pep-storage-account-data-private-sensitive",
                    private_link_service_id=storage_account_data_private_sensitive.id,
                )
            ],
            resource_group_name=props.resource_group_name,
            subnet=network.SubnetArgs(id=props.subnet_data_private_id),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=["custom_dns_configs"],
                    parent=storage_account_data_private_sensitive,
                ),
            ),
            tags=child_tags,
        )
        # Add a private DNS record for each sensitive data endpoint custom DNS config
        network.PrivateDnsZoneGroup(
            f"{storage_account_data_private_sensitive._name}_private_dns_zone_group",
            private_dns_zone_configs=[
                network.PrivateDnsZoneConfigArgs(
                    name=replace_separators(
                        f"{stack_name}-storage-account-data-private-sensitive-to-{dns_zone_name}",
                        "-",
                    ),
                    private_dns_zone_id=props.dns_private_zones[dns_zone_name].id,
                )
                for dns_zone_name in AzureDnsZoneNames.STORAGE_ACCOUNT
            ],
            private_dns_zone_group_name=f"{stack_name}-dzg-storage-account-data-private-sensitive",
            private_endpoint_name=storage_account_data_private_sensitive_endpoint.name,
            resource_group_name=props.resource_group_name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=storage_account_data_private_sensitive),
            ),
        )

        # Give the "Storage Blob Data Owner" role to the Azure admin group
        # for the data resource group
        authorization.RoleAssignment(
            f"{self._name}_data_owner_role_assignment",
            principal_id=props.admin_group_id,
            principal_type=authorization.PrincipalType.GROUP,
            role_assignment_name=str(
                seeded_uuid(f"{stack_name} Storage Blob Data Owner")
            ),
            role_definition_id=Output.concat(
                "/subscriptions/",
                props.subscription_id,
                "/providers/Microsoft.Authorization/roleDefinitions/",
                self.azure_role_ids["Storage Blob Data Owner"],
            ),
            scope=props.resource_group_id,
            opts=child_opts,
        )

        # Deploy data_private_user files storage account
        # - This holds the /home and /mnt/shared containers that are mounted by workspaces
        # - Azure Files has better NFS support but cannot be accessed with Azure Storage Explorer
        # - Allows root-squashing to be configured
        # From https://learn.microsoft.com/en-us/azure/storage/files/files-nfs-protocol
        # - premium file shares are required
        storage_account_data_private_user = storage.StorageAccount(
            f"{self._name}_storage_account_data_private_user",
            access_tier=storage.AccessTier.COOL,
            # Storage account names have a maximum of 24 characters
            account_name=alphanumeric(
                f"{''.join(truncate_tokens(stack_name.split('-'), 16))}userdata{sha256hash(self._name)}"
            )[:24],
            enable_https_traffic_only=False,
            encryption=storage.EncryptionArgs(
                key_source=storage.KeySource.MICROSOFT_STORAGE,
                services=storage.EncryptionServicesArgs(
                    file=storage.EncryptionServiceArgs(
                        enabled=True, key_type=storage.KeyType.ACCOUNT
                    ),
                ),
            ),
            kind=storage.Kind.FILE_STORAGE,
            location=props.location,
            minimum_tls_version=storage.MinimumTlsVersion.TLS1_2,
            network_rule_set=storage.NetworkRuleSetArgs(
                bypass=storage.Bypass.AZURE_SERVICES,
                default_action=storage.DefaultAction.DENY,
                virtual_network_rules=[
                    storage.VirtualNetworkRuleArgs(
                        virtual_network_resource_id=props.subnet_data_private_id,
                    )
                ],
            ),
            resource_group_name=props.resource_group_name,
            sku=storage.SkuArgs(name=storage.SkuName.PREMIUM_ZRS),
            opts=child_opts,
            tags=child_tags,
        )
        storage.FileShare(
            f"{storage_account_data_private_user._name}_files_home",
            access_tier=storage.ShareAccessTier.PREMIUM,
            account_name=storage_account_data_private_user.name,
            enabled_protocols=storage.EnabledProtocols.NFS,
            resource_group_name=props.resource_group_name,
            # Squashing prevents root from creating user home directories
            root_squash=storage.RootSquashType.NO_ROOT_SQUASH,
            share_name="home",
            share_quota=props.storage_quota_gb_home,
            signed_identifiers=[],
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=storage_account_data_private_user)
            ),
        )
        storage.FileShare(
            f"{storage_account_data_private_user._name}_files_shared",
            access_tier=storage.ShareAccessTier.PREMIUM,
            account_name=storage_account_data_private_user.name,
            enabled_protocols=storage.EnabledProtocols.NFS,
            resource_group_name=props.resource_group_name,
            root_squash=storage.RootSquashType.ROOT_SQUASH,
            share_name="shared",
            share_quota=props.storage_quota_gb_shared,
            signed_identifiers=[],
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=storage_account_data_private_user)
            ),
        )
        # Set up a private endpoint for the user data storage account
        storage_account_data_private_user_endpoint = network.PrivateEndpoint(
            f"{storage_account_data_private_user._name}_private_endpoint",
            location=props.location,
            private_endpoint_name=f"{stack_name}-pep-storage-account-data-private-user",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["file"],
                    name=f"{stack_name}-cnxn-pep-storage-account-data-private-user",
                    private_link_service_id=storage_account_data_private_user.id,
                )
            ],
            resource_group_name=props.resource_group_name,
            subnet=network.SubnetArgs(id=props.subnet_data_private_id),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=["custom_dns_configs"],
                    parent=storage_account_data_private_user,
                ),
            ),
            tags=child_tags,
        )
        # Add a private DNS record for each user data endpoint custom DNS config
        network.PrivateDnsZoneGroup(
            f"{storage_account_data_private_user._name}_private_dns_zone_group",
            private_dns_zone_configs=[
                network.PrivateDnsZoneConfigArgs(
                    name=replace_separators(
                        f"{stack_name}-storage-account-data-private-user-to-{dns_zone_name}",
                        "-",
                    ),
                    private_dns_zone_id=props.dns_private_zones[dns_zone_name].id,
                )
                for dns_zone_name in AzureDnsZoneNames.STORAGE_ACCOUNT
            ],
            private_dns_zone_group_name=f"{stack_name}-dzg-storage-account-data-private-user",
            private_endpoint_name=storage_account_data_private_user_endpoint.name,
            resource_group_name=props.resource_group_name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=storage_account_data_private_user)
            ),
        )

        # Register outputs
        self.sre_fqdn_certificate_secret_id = sre_fqdn_certificate.secret_id
        self.storage_account_data_private_user_name = (
            storage_account_data_private_user.name
        )
        self.storage_account_data_private_sensitive_id = (
            storage_account_data_private_sensitive.id
        )
        self.storage_account_data_private_sensitive_name = (
            storage_account_data_private_sensitive.name
        )
        self.storage_account_data_configuration_key = Output.secret(
            storage_account_data_configuration_keys.apply(
                lambda keys: keys.keys[0].value
            )
        )
        self.storage_account_data_configuration_name = (
            storage_account_data_configuration.name
        )
        self.managed_identity = identity_key_vault_reader
        self.password_nexus_admin = Output.secret(password_nexus_admin.result)
        self.password_database_service_admin = Output.secret(
            password_database_service_admin.result
        )
        self.password_dns_server_admin = Output.secret(
            Output.from_input(props.password_dns_server_admin).apply(
                lambda password: password.result
            )
        )
        self.password_gitea_database_admin = Output.secret(
            password_gitea_database_admin.result
        )
        self.password_hedgedoc_database_admin = Output.secret(
            password_hedgedoc_database_admin.result
        )
        self.password_user_database_admin = Output.secret(
            password_user_database_admin.result
        )
        self.password_workspace_admin = Output.secret(password_workspace_admin.result)

        # Register exports
        self.exports = {
            "key_vault_name": key_vault.name,
            "password_user_database_admin_secret": kvs_password_user_database_admin.name,
        }
