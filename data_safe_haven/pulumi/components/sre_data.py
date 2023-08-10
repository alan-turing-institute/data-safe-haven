"""Pulumi component for SRE data"""
from collections.abc import Sequence

from pulumi import ComponentResource, Config, Input, Output, ResourceOptions
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
    ordered_private_dns_zones,
    replace_separators,
    sha256hash,
    truncate_tokens,
)
from data_safe_haven.pulumi.common import (
    get_id_from_subnet,
    get_name_from_rg,
)
from data_safe_haven.pulumi.dynamic.blob_container_acl import (
    BlobContainerAcl,
    BlobContainerAclProps,
)
from data_safe_haven.pulumi.dynamic.ssl_certificate import (
    SSLCertificate,
    SSLCertificateProps,
)


class SREDataProps:
    """Properties for SREDataComponent"""

    def __init__(
        self,
        admin_email_address: Input[str],
        admin_group_id: Input[str],
        admin_ip_addresses: Input[Sequence[str]],
        data_provider_ip_addresses: Input[Sequence[str]],
        dns_record: Input[network.RecordSet],
        location: Input[str],
        networking_resource_group: Input[resources.ResourceGroup],
        pulumi_opts: Config,
        sre_fqdn: Input[str],
        subnet_data_configuration: Input[network.GetSubnetResult],
        subnet_data_private: Input[network.GetSubnetResult],
        subscription_id: Input[str],
        subscription_name: Input[str],
        tenant_id: Input[str],
    ) -> None:
        self.admin_email_address = admin_email_address
        self.admin_group_id = admin_group_id
        self.approved_ip_addresses = Output.all(
            admin_ip_addresses, data_provider_ip_addresses
        ).apply(
            lambda address_lists: {
                ip for address_list in address_lists for ip in address_list
            }
        )
        self.dns_record = dns_record
        self.location = location
        self.networking_resource_group_name = Output.from_input(
            networking_resource_group
        ).apply(get_name_from_rg)
        self.password_database_service_admin = self.get_secret(
            pulumi_opts, "password-database-service-admin"
        )
        self.password_gitea_database_admin = self.get_secret(
            pulumi_opts, "password-gitea-database-admin"
        )
        self.password_hedgedoc_database_admin = self.get_secret(
            pulumi_opts, "password-hedgedoc-database-admin"
        )
        self.password_nexus_admin = self.get_secret(pulumi_opts, "password-nexus-admin")
        self.password_user_database_admin = self.get_secret(
            pulumi_opts, "password-user-database-admin"
        )
        self.password_workspace_admin = self.get_secret(
            pulumi_opts, "password-workspace-admin"
        )
        self.private_dns_zone_base_id = self.get_secret(
            pulumi_opts, "shm-networking-private_dns_zone_base_id"
        )
        self.sre_fqdn = sre_fqdn
        self.subnet_data_configuration_id = Output.from_input(
            subnet_data_configuration
        ).apply(get_id_from_subnet)
        self.subnet_data_private_id = Output.from_input(subnet_data_private).apply(
            get_id_from_subnet
        )
        self.subscription_id = subscription_id
        self.subscription_name = subscription_name
        self.tenant_id = tenant_id

    def get_secret(self, pulumi_opts: Config, secret_name: str) -> Output[str]:
        return Output.secret(pulumi_opts.require(secret_name))


class SREDataComponent(ComponentResource):
    """Deploy SRE data with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREDataProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:DataComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-data",
            opts=child_opts,
        )

        # Define Key Vault reader
        identity_key_vault_reader = managedidentity.UserAssignedIdentity(
            f"{self._name}_id_key_vault_reader",
            location=props.location,
            resource_group_name=resource_group.name,
            resource_name_=f"{stack_name}-id-key-vault-reader",
            opts=child_opts,
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
                tenant_id=props.tenant_id,
            ),
            resource_group_name=resource_group.name,
            vault_name=f"{''.join(truncate_tokens(stack_name.split('-'), 17))}secrets",  # maximum of 24 characters
            opts=child_opts,
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
                networking_resource_group_name=props.networking_resource_group_name,
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

        # Deploy key vault secrets
        keyvault.Secret(
            f"{self._name}_kvs_password_database_service_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=props.password_database_service_admin
            ),
            resource_group_name=resource_group.name,
            secret_name="password-database-service-admin",
            vault_name=key_vault.name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=key_vault)),
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_gitea_database_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=props.password_gitea_database_admin
            ),
            resource_group_name=resource_group.name,
            secret_name="password-gitea-database-admin",
            vault_name=key_vault.name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=key_vault)),
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_hedgedoc_database_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=props.password_hedgedoc_database_admin
            ),
            resource_group_name=resource_group.name,
            secret_name="password-hedgedoc-database-admin",
            vault_name=key_vault.name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=key_vault)),
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_nexus_admin",
            properties=keyvault.SecretPropertiesArgs(value=props.password_nexus_admin),
            resource_group_name=resource_group.name,
            secret_name="password-nexus-admin",
            vault_name=key_vault.name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=key_vault)),
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_user_database_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=props.password_user_database_admin
            ),
            resource_group_name=resource_group.name,
            secret_name="password-user-database-admin",
            vault_name=key_vault.name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=key_vault)),
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_workspace_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=props.password_workspace_admin
            ),
            resource_group_name=resource_group.name,
            secret_name="password-workspace-admin",
            vault_name=key_vault.name,
            opts=ResourceOptions(parent=key_vault),
        )

        # Deploy configuration data storage account
        storage_account_data_configuration = storage.StorageAccount(
            f"{self._name}_storage_account_data_configuration",
            # Note that account names have a maximum of 24 characters
            account_name=alphanumeric(
                f"{''.join(truncate_tokens(stack_name.split('-'), 14))}configdata"
            )[:24],
            kind=storage.Kind.STORAGE_V2,
            resource_group_name=resource_group.name,
            sku=storage.SkuArgs(name=storage.SkuName.STANDARD_GRS),
            opts=child_opts,
        )
        # Retrieve configuration data storage account keys
        storage_account_data_configuration_keys = Output.all(
            account_name=storage_account_data_configuration.name,
            resource_group_name=resource_group.name,
        ).apply(
            lambda kwargs: storage.list_storage_account_keys(
                account_name=kwargs["account_name"],
                resource_group_name=kwargs["resource_group_name"],
            )
        )
        # Set up a private endpoint for the configuration data storage account
        storage_account_data_configuration_private_endpoint = network.PrivateEndpoint(
            f"{self._name}_storage_account_data_configuration_private_endpoint",
            location=props.location,
            private_endpoint_name=f"{stack_name}-pep-storage-account-data-configuration",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["file"],
                    name=f"{stack_name}-cnxn-pep-storage-account-data-configuration",
                    private_link_service_id=storage_account_data_configuration.id,
                )
            ],
            resource_group_name=resource_group.name,
            subnet=network.SubnetArgs(id=props.subnet_data_configuration_id),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=storage_account_data_configuration)
            ),
        )
        # Add a private DNS record for each configuration data endpoint custom DNS config
        network.PrivateDnsZoneGroup(
            f"{self._name}_storage_account_data_configuration_private_dns_zone_group",
            private_dns_zone_configs=[
                network.PrivateDnsZoneConfigArgs(
                    name=replace_separators(
                        f"{stack_name}-storage-account-data-configuration-to-{dns_zone_name}",
                        "-",
                    ),
                    private_dns_zone_id=Output.concat(
                        props.private_dns_zone_base_id, dns_zone_name
                    ),
                )
                for dns_zone_name in ordered_private_dns_zones("Storage account")
            ],
            private_dns_zone_group_name=f"{stack_name}-dzg-storage-account-data-configuration",
            private_endpoint_name=storage_account_data_configuration_private_endpoint.name,
            resource_group_name=resource_group.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=storage_account_data_configuration)
            ),
        )

        # Deploy sensitive data blob storage account
        # - Azure blobs have worse NFS support but can be accessed with Azure Storage Explorer
        # - Store the /data and /output folders here
        storage_account_data_private_sensitive = storage.StorageAccount(
            f"{self._name}_storage_account_data_private_sensitive",
            # Storage account names have a maximum of 24 characters
            account_name=alphanumeric(
                f"{''.join(truncate_tokens(stack_name.split('-'), 11))}sensitivedata{sha256hash(self._name)}"
            )[:24],
            enable_https_traffic_only=True,
            enable_nfs_v3=True,
            encryption=storage.EncryptionArgs(
                key_source=storage.KeySource.MICROSOFT_STORAGE,
                services=storage.EncryptionServicesArgs(
                    blob=storage.EncryptionServiceArgs(
                        enabled=True, key_type=storage.KeyType.ACCOUNT
                    ),
                    file=storage.EncryptionServiceArgs(
                        enabled=True, key_type=storage.KeyType.ACCOUNT
                    ),
                ),
            ),
            kind=storage.Kind.BLOCK_BLOB_STORAGE,
            is_hns_enabled=True,
            location=props.location,
            network_rule_set=storage.NetworkRuleSetArgs(
                bypass=storage.Bypass.AZURE_SERVICES,
                default_action=storage.DefaultAction.DENY,
                ip_rules=Output.from_input(props.approved_ip_addresses).apply(
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
                        virtual_network_resource_id=props.subnet_data_private_id,
                    )
                ],
            ),
            resource_group_name=resource_group.name,
            sku=storage.SkuArgs(name=storage.SkuName.PREMIUM_ZRS),
            opts=child_opts,
        )
        # Give the "Storage Blob Data Owner" role to the Azure admin group
        authorization.RoleAssignment(
            f"{self._name}_storage_account_data_private_sensitive_data_owner_role_assignment",
            principal_id=props.admin_group_id,
            principal_type=authorization.PrincipalType.GROUP,
            role_assignment_name="b7e6dc6d-f1e8-4753-8033-0f276bb0955b",  # Storage Blob Data Owner
            role_definition_id=Output.concat(
                "/subscriptions/",
                props.subscription_id,
                "/providers/Microsoft.Authorization/roleDefinitions/b7e6dc6d-f1e8-4753-8033-0f276bb0955b",
            ),
            scope=storage_account_data_private_sensitive.id,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=storage_account_data_private_sensitive),
            ),
        )
        # Deploy storage containers
        storage_container_egress = storage.BlobContainer(
            f"{self._name}_storage_container_egress",
            account_name=storage_account_data_private_sensitive.name,
            container_name="egress",
            default_encryption_scope="$account-encryption-key",
            deny_encryption_scope_override=False,
            public_access=storage.PublicAccess.NONE,
            resource_group_name=resource_group.name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=storage_account_data_private_sensitive),
            ),
        )
        storage_container_ingress = storage.BlobContainer(
            f"{self._name}_storage_container_ingress",
            account_name=storage_account_data_private_sensitive.name,
            container_name="ingress",
            default_encryption_scope="$account-encryption-key",
            deny_encryption_scope_override=False,
            public_access=storage.PublicAccess.NONE,
            resource_group_name=resource_group.name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=storage_account_data_private_sensitive),
            ),
        )
        # Set storage container ACLs
        BlobContainerAcl(
            f"{self._name}_storage_container_egress_acl",
            BlobContainerAclProps(
                acl_user="rwx",
                acl_group="rwx",
                acl_other="rwx",
                # due to an Azure bug `apply_default_permissions=True` also
                # gives ownership of the fileshare to user 65533 (preventing
                # use inside the SRE)
                apply_default_permissions=False,
                container_name=storage_container_egress.name,
                resource_group_name=resource_group.name,
                storage_account_name=storage_account_data_private_sensitive.name,
                subscription_name=props.subscription_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=storage_container_egress)
            ),
        )
        BlobContainerAcl(
            f"{self._name}_storage_container_ingress_acl",
            BlobContainerAclProps(
                acl_user="rwx",
                acl_group="r-x",
                acl_other="r-x",
                # ensure that the above permissions are also set on any newly
                # created files (eg. with Azure Storage Explorer)
                apply_default_permissions=True,
                container_name=storage_container_ingress.name,
                resource_group_name=resource_group.name,
                storage_account_name=storage_account_data_private_sensitive.name,
                subscription_name=props.subscription_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=storage_container_ingress)
            ),
        )
        # Set up a private endpoint for the sensitive data storage account
        storage_account_data_private_sensitive_endpoint = network.PrivateEndpoint(
            f"{self._name}_storage_account_data_private_sensitive_private_endpoint",
            location=props.location,
            private_endpoint_name=f"{stack_name}-pep-storage-account-data-private-sensitive",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["blob"],
                    name=f"{stack_name}-cnxn-pep-storage-account-data-private-sensitive",
                    private_link_service_id=storage_account_data_private_sensitive.id,
                )
            ],
            resource_group_name=resource_group.name,
            subnet=network.SubnetArgs(id=props.subnet_data_private_id),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=storage_account_data_private_sensitive),
            ),
        )
        # Add a private DNS record for each sensitive data endpoint custom DNS config
        network.PrivateDnsZoneGroup(
            f"{self._name}_storage_account_data_private_sensitive_private_dns_zone_group",
            private_dns_zone_configs=[
                network.PrivateDnsZoneConfigArgs(
                    name=replace_separators(
                        f"{stack_name}-storage-account-data-private-sensitive-to-{dns_zone_name}",
                        "-",
                    ),
                    private_dns_zone_id=Output.concat(
                        props.private_dns_zone_base_id, dns_zone_name
                    ),
                )
                for dns_zone_name in ordered_private_dns_zones("Storage account")
            ],
            private_dns_zone_group_name=f"{stack_name}-dzg-storage-account-data-private-sensitive",
            private_endpoint_name=storage_account_data_private_sensitive_endpoint.name,
            resource_group_name=resource_group.name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=storage_account_data_private_sensitive),
            ),
        )

        # Deploy data_private_user files storage account
        # - Azure Files has better NFS support and cannot be accessed with Azure Storage Explorer
        # - Allows root-squashing to be configured
        # - Store the /home and /shared folders here
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
            network_rule_set=storage.NetworkRuleSetArgs(
                bypass=storage.Bypass.AZURE_SERVICES,
                default_action=storage.DefaultAction.DENY,
                virtual_network_rules=[
                    storage.VirtualNetworkRuleArgs(
                        virtual_network_resource_id=props.subnet_data_private_id,
                    )
                ],
            ),
            resource_group_name=resource_group.name,
            sku=storage.SkuArgs(name=storage.SkuName.PREMIUM_ZRS),
            opts=child_opts,
        )
        storage.FileShare(
            f"{self._name}_storage_container_home",
            access_tier=storage.ShareAccessTier.PREMIUM,
            account_name=storage_account_data_private_user.name,
            enabled_protocols=storage.EnabledProtocols.NFS,
            resource_group_name=resource_group.name,
            # Squashing prevents root from creating user home directories
            root_squash=storage.RootSquashType.NO_ROOT_SQUASH,
            share_name="home",
            share_quota=1024,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=storage_account_data_private_user)
            ),
        )
        storage.FileShare(
            f"{self._name}_storage_container_shared",
            access_tier=storage.ShareAccessTier.PREMIUM,
            account_name=storage_account_data_private_user.name,
            enabled_protocols=storage.EnabledProtocols.NFS,
            resource_group_name=resource_group.name,
            root_squash=storage.RootSquashType.ROOT_SQUASH,
            share_name="shared",
            share_quota=1024,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=storage_account_data_private_user)
            ),
        )
        # Set up a private endpoint for the user data storage account
        storage_account_data_private_user_endpoint = network.PrivateEndpoint(
            f"{self._name}_storage_account_data_private_user_private_endpoint",
            location=props.location,
            private_endpoint_name=f"{stack_name}-pep-storage-account-data-private-user",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["file"],
                    name=f"{stack_name}-cnxn-pep-storage-account-data-private-user",
                    private_link_service_id=storage_account_data_private_user.id,
                )
            ],
            resource_group_name=resource_group.name,
            subnet=network.SubnetArgs(id=props.subnet_data_private_id),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=storage_account_data_private_user)
            ),
        )
        # Add a private DNS record for each user data endpoint custom DNS config
        network.PrivateDnsZoneGroup(
            f"{self._name}_storage_account_data_private_user_private_dns_zone_group",
            private_dns_zone_configs=[
                network.PrivateDnsZoneConfigArgs(
                    name=replace_separators(
                        f"{stack_name}-storage-account-data-private-user-to-{dns_zone_name}",
                        "-",
                    ),
                    private_dns_zone_id=Output.concat(
                        props.private_dns_zone_base_id, dns_zone_name
                    ),
                )
                for dns_zone_name in ordered_private_dns_zones("Storage account")
            ],
            private_dns_zone_group_name=f"{stack_name}-dzg-storage-account-data-private-user",
            private_endpoint_name=storage_account_data_private_user_endpoint.name,
            resource_group_name=resource_group.name,
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
            storage_account_data_configuration_keys.keys[0].value
        )
        self.storage_account_data_configuration_name = (
            storage_account_data_configuration.name
        )
        self.managed_identity = identity_key_vault_reader
        self.password_nexus_admin = Output.secret(props.password_nexus_admin)
        self.password_database_service_admin = Output.secret(
            props.password_database_service_admin
        )
        self.password_gitea_database_admin = Output.secret(
            props.password_gitea_database_admin
        )
        self.password_hedgedoc_database_admin = Output.secret(
            props.password_hedgedoc_database_admin
        )
        self.password_user_database_admin = Output.secret(
            props.password_user_database_admin
        )
        self.password_workspace_admin = Output.secret(props.password_workspace_admin)
        self.resource_group_name = resource_group.name
