"""Pulumi component for SRE state"""
# Standard library imports
from typing import Optional, Sequence

# Third party imports
from pulumi import Config, ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import keyvault, managedidentity, network, resources, storage

# Local imports
from data_safe_haven.external.interface import AzureIPv4Range
from data_safe_haven.helpers import alphanumeric, sha256hash, truncate_tokens
from data_safe_haven.pulumi.common.transformations import get_name_from_rg
from ..dynamic.ssl_certificate import SSLCertificate, SSLCertificateProps


class SREStateProps:
    """Properties for SREStateComponent"""

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
        self.shm_storage_account_name = self.get_secret(
            pulumi_opts, "shm-state_storage_account_name"
        )
        self.shm_storage_resource_group_name = self.get_secret(
            pulumi_opts, "shm-state_resource_group_name"
        )
        self.sre_fqdn = sre_fqdn
        self.subscription_name = subscription_name
        self.tenant_id = tenant_id

    def get_secret(self, pulumi_opts: Config, secret_name: str) -> Output[str]:
        return Output.secret(pulumi_opts.require(secret_name))


class SREStateComponent(ComponentResource):
    """Deploy SRE state with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SREStateProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:sre:SREStateComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-state",
            opts=child_opts,
        )

        # Define Key Vault reader
        key_vault_reader = managedidentity.UserAssignedIdentity(
            f"{self._name}_key_vault_reader",
            location=props.location,
            resource_group_name=resource_group.name,
            resource_name_=f"{stack_name}-id-key-vault-reader",
            opts=child_opts,
        )

        # Define SRE KeyVault
        key_vault = keyvault.Vault(
            f"{self._name}_key_vault",
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
                        object_id=key_vault_reader.principal_id,
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
            account_name=alphanumeric(
                f"{''.join(truncate_tokens(stack_name.split('-'), 19))}state{sha256hash(self._name)}"
            )[
                :24
            ],  # maximum of 24 characters
            kind="StorageV2",
            resource_group_name=resource_group.name,
            sku=storage.SkuArgs(name="Standard_LRS"),
            opts=child_opts,
        )

        # Retrieve storage account keys
        storage_account_state_keys = storage.list_storage_account_keys(
            account_name=storage_account_state.name,
            resource_group_name=resource_group.name,
        )

        # Deploy data account
        storage_account_data = storage.StorageAccount(
            f"{self._name}_storage_account_data",
            access_tier=storage.AccessTier.COOL,
            account_name=alphanumeric(
                f"{''.join(truncate_tokens(stack_name.split('-'), 20))}data{sha256hash(self._name)}"
            )[
                :24
            ],  # maximum of 24 characters
            enable_https_traffic_only=True,
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
            kind=storage.Kind.STORAGE_V2,
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
            ),
            resource_group_name=resource_group.name,
            sku=storage.SkuArgs(name=storage.SkuName.STANDARD_GRS),
            opts=child_opts,
        )
        # Deploy storage containers
        egress_container = storage.BlobContainer(
            f"{self._name}_st_data_egress",
            account_name=storage_account_data.name,
            container_name="egress",
            default_encryption_scope="$account-encryption-key",
            deny_encryption_scope_override=False,
            public_access=storage.PublicAccess.NONE,
            resource_group_name=resource_group.name,
            opts=child_opts,
        )
        ingress_container = storage.BlobContainer(
            f"{self._name}_st_data_ingress",
            account_name=storage_account_data.name,
            container_name="ingress",
            default_encryption_scope="$account-encryption-key",
            deny_encryption_scope_override=False,
            public_access=storage.PublicAccess.NONE,
            resource_group_name=resource_group.name,
            opts=child_opts,
        )

        # Register outputs
        self.access_key = Output.secret(storage_account_state_keys.keys[0].value)
        self.account_name = Output.from_input(storage_account_state.name)
        self.certificate_secret_id = certificate.secret_id
        self.managed_identity = key_vault_reader
        self.password_secure_research_desktop_admin = (
            props.password_secure_research_desktop_admin
        )
        self.password_user_database_admin = props.password_user_database_admin
        self.resource_group_name = resource_group.name
