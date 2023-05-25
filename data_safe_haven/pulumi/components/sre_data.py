"""Pulumi component for SRE state"""
# Standard library imports
from typing import Optional, Sequence

# Third party imports
from pulumi import Config, ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import (
    authorization,
    keyvault,
    managedidentity,
    network,
    resources,
    storage,
)

# Local imports
from data_safe_haven.external.interface import AzureIPv4Range
from data_safe_haven.helpers import (
    alphanumeric,
    ordered_private_dns_zones,
    replace_separators,
    sha256hash,
    truncate_tokens,
)
from data_safe_haven.pulumi.common.transformations import (
    get_id_from_subnet,
    get_name_from_rg,
)
from ..dynamic.blob_container_acl import BlobContainerAcl, BlobContainerAclProps
from ..dynamic.ssl_certificate import SSLCertificate, SSLCertificateProps


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
        subnet_private_data: Input[network.GetSubnetResult],
        subscription_id: Input[str],
        subscription_name: Input[str],
        tenant_id: Input[str],
    ):
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
        self.password_secure_research_desktop_admin = self.get_secret(
            pulumi_opts, "password-secure-research-desktop-admin"
        )
        self.password_user_database_admin = self.get_secret(
            pulumi_opts, "password-user-database-admin"
        )
        self.private_dns_zone_base_id = self.get_secret(
            pulumi_opts, "shm-networking-private_dns_zone_base_id"
        )
        self.sre_fqdn = sre_fqdn
        self.subnet_private_data_id = Output.from_input(subnet_private_data).apply(
            get_id_from_subnet
        )
        self.subscription_id = subscription_id
        self.subscription_name = subscription_name
        self.tenant_id = tenant_id

    def get_secret(self, pulumi_opts: Config, secret_name: str) -> Output[str]:
        return Output.secret(pulumi_opts.require(secret_name))


class SREDataComponent(ComponentResource):
    """Deploy SRE state with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SREDataProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:sre:SREDataComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

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
        certificate = SSLCertificate(
            f"{self._name}_ssl_certificate",
            SSLCertificateProps(
                certificate_secret_name="ssl-certificate-sre-remote-desktop",
                domain_name=props.sre_fqdn,
                admin_email_address=props.admin_email_address,
                key_vault_name=key_vault.name,
                networking_resource_group_name=props.networking_resource_group_name,
                subscription_name=props.subscription_name,
            ),
            opts=ResourceOptions.merge(
                ResourceOptions(
                    depends_on=[props.dns_record]
                ),  # we need the delegation NS record to exist before generating the certificate
                child_opts,
            ),
        )

        # Deploy key vault secrets
        password_secure_research_desktop_admin = keyvault.Secret(
            f"{self._name}_kvs_password_secure_research_desktop_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=props.password_secure_research_desktop_admin
            ),
            resource_group_name=resource_group.name,
            secret_name="password-secure-research-desktop-admin",
            vault_name=key_vault.name,
            opts=child_opts,
        )
        password_user_database_admin = keyvault.Secret(
            f"{self._name}_kvs_password_user_database_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=props.password_user_database_admin
            ),
            resource_group_name=resource_group.name,
            secret_name="password-user-database-admin",
            vault_name=key_vault.name,
            opts=child_opts,
        )

        # Deploy state storage account
        storage_account_state = storage.StorageAccount(
            f"{self._name}_storage_account_state",
            # Note that account names have a maximum of 24 characters
            account_name=alphanumeric(
                f"{''.join(truncate_tokens(stack_name.split('-'), 19))}state"
            )[:24],
            kind=storage.Kind.STORAGE_V2,
            resource_group_name=resource_group.name,
            sku=storage.SkuArgs(name=storage.SkuName.STANDARD_GRS),
            opts=child_opts,
        )
        # Retrieve storage account keys
        storage_account_state_keys = storage.list_storage_account_keys(
            account_name=storage_account_state.name,
            resource_group_name=resource_group.name,
        )

        # Deploy secure data blob storage account
        # - Azure blobs have worse NFS support but can be accessed with Azure Storage Explorer
        # - Store the /data and /output folders here
        storage_account_securedata = storage.StorageAccount(
            f"{self._name}_storage_account_securedata",
            # access_tier=storage.AccessTier.COOL,
            # Storage account names have a maximum of 24 characters
            account_name=alphanumeric(
                f"{''.join(truncate_tokens(stack_name.split('-'), 14))}securedata{sha256hash(self._name)}"
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
            kind=storage.Kind.BLOCK_BLOB_STORAGE, #storage.Kind.STORAGE_V2,
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
                        for ip_address in AzureIPv4Range.from_cidr(ip_range).all()
                    ]
                ),
                virtual_network_rules=[
                    storage.VirtualNetworkRuleArgs(
                        virtual_network_resource_id=props.subnet_private_data_id,
                    )
                ],
            ),
            resource_group_name=resource_group.name,
            #sku=storage.SkuArgs(name=storage.SkuName.STANDARD_ZRS),
            sku=storage.SkuArgs(name=storage.SkuName.PREMIUM_ZRS),
            opts=child_opts,
        )
        # Give the "Storage Blob Data Owner" role to the Azure admin group
        storage_account_securedata_data_owner_role_assignment = authorization.RoleAssignment(
            f"{self._name}_storage_account_securedata_data_owner_role_assignment",
            principal_id=props.admin_group_id,
            principal_type=authorization.PrincipalType.GROUP,
            role_assignment_name="b7e6dc6d-f1e8-4753-8033-0f276bb0955b",  # Storage Blob Data Owner
            role_definition_id=Output.concat(
                "/subscriptions/",
                props.subscription_id,
                "/providers/Microsoft.Authorization/roleDefinitions/b7e6dc6d-f1e8-4753-8033-0f276bb0955b",
            ),
            scope=storage_account_securedata.id,
        )
        # Deploy storage containers
        storage_container_egress = storage.BlobContainer(
            f"{self._name}_storage_container_egress",
            account_name=storage_account_securedata.name,
            container_name="egress",
            default_encryption_scope="$account-encryption-key",
            deny_encryption_scope_override=False,
            public_access=storage.PublicAccess.NONE,
            resource_group_name=resource_group.name,
            opts=child_opts,
        )
        storage_container_ingress = storage.BlobContainer(
            f"{self._name}_storage_container_ingress",
            account_name=storage_account_securedata.name,
            container_name="ingress",
            default_encryption_scope="$account-encryption-key",
            deny_encryption_scope_override=False,
            public_access=storage.PublicAccess.NONE,
            resource_group_name=resource_group.name,
            opts=child_opts,
        )
        # Set storage container ACLs
        storage_container_egress_acl = BlobContainerAcl(
            f"{self._name}_storage_container_egress_acl",
            BlobContainerAclProps(
                acl_user="rwx",
                acl_group="rwx",
                acl_other="rwx",
                container_name=storage_container_egress.name,
                resource_group_name=resource_group.name,
                storage_account_name=storage_account_securedata.name,
                subscription_name=props.subscription_name,
            ),
            opts=child_opts,
        )
        storage_container_ingress_acl = BlobContainerAcl(
            f"{self._name}_storage_container_ingress_acl",
            BlobContainerAclProps(
                acl_user="rwx",
                acl_group="r-x",
                acl_other="r-x",
                container_name=storage_container_ingress.name,
                resource_group_name=resource_group.name,
                storage_account_name=storage_account_securedata.name,
                subscription_name=props.subscription_name,
            ),
            opts=child_opts,
        )
        # Set up a private endpoint for the securedata data account
        storage_account_securedata_endpoint = network.PrivateEndpoint(
            f"{self._name}_storage_account_securedata_private_endpoint",
            location=props.location,
            private_endpoint_name=f"{stack_name}-pep-storage-account-securedata",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["blob"],
                    name=f"{stack_name}-cnxn-pep-storage-account-securedata",
                    private_link_service_id=storage_account_securedata.id,
                )
            ],
            resource_group_name=resource_group.name,
            subnet=network.SubnetArgs(id=props.subnet_private_data_id),
            opts=child_opts,
        )
        # Add a private DNS record for each securedata data custom DNS config
        storage_account_securedata_private_dns_zone_group = network.PrivateDnsZoneGroup(
            f"{self._name}_storage_account_securedata_private_dns_zone_group",
            private_dns_zone_configs=[
                network.PrivateDnsZoneConfigArgs(
                    name=replace_separators(
                        f"{stack_name}-storage-account-securedata-to-{dns_zone_name}",
                        "-",
                    ),
                    private_dns_zone_id=Output.concat(
                        props.private_dns_zone_base_id, dns_zone_name
                    ),
                )
                for dns_zone_name in ordered_private_dns_zones("Storage account")
            ],
            private_dns_zone_group_name=f"{stack_name}-dzg-storage-account-securedata",
            private_endpoint_name=storage_account_securedata_endpoint.name,
            resource_group_name=resource_group.name,
        )

        # Deploy userdata files storage account
        # - Azure Files has better NFS support and cannot be accessed with Azure Storage Explorer
        # - Allows root-squashing to be configured
        # - Store the /home and /shared folders here
        storage_account_userdata = storage.StorageAccount(
            f"{self._name}_storage_account_userdata",
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
                        virtual_network_resource_id=props.subnet_private_data_id,
                    )
                ],
            ),
            resource_group_name=resource_group.name,
            sku=storage.SkuArgs(name=storage.SkuName.PREMIUM_ZRS),
            opts=child_opts,
        )
        file_container_home = storage.FileShare(
            f"{self._name}_storage_container_home",
            access_tier=storage.ShareAccessTier.PREMIUM,
            account_name=storage_account_userdata.name,
            enabled_protocols=storage.EnabledProtocols.NFS,
            resource_group_name=resource_group.name,
            root_squash=storage.RootSquashType.NO_ROOT_SQUASH,  # Squashing prevents root from creating user home directories
            share_name="home",
            share_quota=1024,
            opts=child_opts,
        )
        file_container_shared = storage.FileShare(
            f"{self._name}_storage_container_shared",
            access_tier=storage.ShareAccessTier.PREMIUM,
            account_name=storage_account_userdata.name,
            enabled_protocols=storage.EnabledProtocols.NFS,
            resource_group_name=resource_group.name,
            root_squash=storage.RootSquashType.ROOT_SQUASH,
            share_name="shared",
            share_quota=1024,
            opts=child_opts,
        )
        # Set up a private endpoint for the userdata storage account
        storage_account_userdata_endpoint = network.PrivateEndpoint(
            f"{self._name}_storage_account_userdata_private_endpoint",
            location=props.location,
            private_endpoint_name=f"{stack_name}-pep-storage-account-userdata",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["file"],
                    name=f"{stack_name}-cnxn-pep-storage-account-userdata",
                    private_link_service_id=storage_account_userdata.id,
                )
            ],
            resource_group_name=resource_group.name,
            subnet=network.SubnetArgs(id=props.subnet_private_data_id),
            opts=child_opts,
        )
        # Add a private DNS record for each userdata custom DNS config
        storage_account_userdata_private_dns_zone_group = network.PrivateDnsZoneGroup(
            f"{self._name}_storage_account_userdata_private_dns_zone_group",
            private_dns_zone_configs=[
                network.PrivateDnsZoneConfigArgs(
                    name=replace_separators(
                        f"{stack_name}-storage-account-userdata-to-{dns_zone_name}", "-"
                    ),
                    private_dns_zone_id=Output.concat(
                        props.private_dns_zone_base_id, dns_zone_name
                    ),
                )
                for dns_zone_name in ordered_private_dns_zones("Storage account")
            ],
            private_dns_zone_group_name=f"{stack_name}-dzg-storage-account-data",
            private_endpoint_name=storage_account_userdata_endpoint.name,
            resource_group_name=resource_group.name,
        )

        # Register outputs
        self.storage_account_userdata_name = storage_account_userdata.name
        self.storage_account_securedata_name = storage_account_securedata.name
        self.storage_account_state_key = Output.secret(
            storage_account_state_keys.keys[0].value
        )
        self.storage_account_state_name = storage_account_state.name
        self.certificate_secret_id = certificate.secret_id
        self.managed_identity = identity_key_vault_reader
        self.password_secure_research_desktop_admin = (
            props.password_secure_research_desktop_admin
        )
        self.password_user_database_admin = props.password_user_database_admin
        self.resource_group_name = resource_group.name
