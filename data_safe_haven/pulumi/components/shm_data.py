"""Pulumi component for SHM state"""
# Standard library imports
from collections.abc import Sequence

# Third party imports
from pulumi import ComponentResource, Config, Input, Output, ResourceOptions
from pulumi_azure_native import keyvault, resources, storage

# Local imports
from data_safe_haven.external import AzureIPv4Range
from data_safe_haven.functions import alphanumeric, replace_separators, truncate_tokens


class SHMDataProps:
    """Properties for SHMDataComponent"""

    def __init__(
        self,
        admin_group_id: Input[str],
        admin_ip_addresses: Input[Sequence[str]],
        location: Input[str],
        pulumi_opts: Config,
        tenant_id: Input[str],
    ):
        self.admin_group_id = admin_group_id
        self.admin_ip_addresses = admin_ip_addresses
        self.location = location
        self.password_domain_admin = self.get_secret(pulumi_opts, "password-domain-admin")
        self.password_domain_azure_ad_connect = self.get_secret(pulumi_opts, "password-domain-azure-ad-connect")
        self.password_domain_computer_manager = self.get_secret(pulumi_opts, "password-domain-computer-manager")
        self.password_domain_searcher = self.get_secret(pulumi_opts, "password-domain-ldap-searcher")
        self.password_update_server_linux_admin = self.get_secret(pulumi_opts, "password-update-server-linux-admin")
        self.tenant_id = tenant_id

    def get_secret(self, pulumi_opts: Config, secret_name: str) -> Output[str]:
        return Output.secret(pulumi_opts.require(secret_name))


class SHMDataComponent(ComponentResource):
    """Deploy SHM state with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        shm_name: str,
        props: SHMDataProps,
        opts: ResourceOptions | None = None,
    ):
        super().__init__("dsh:shm:DataComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-data",
            opts=child_opts,
        )

        # Deploy key vault
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
                    )
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
            vault_name=f"{replace_separators(stack_name)[:17]}secrets",  # maximum of 24 characters
            opts=child_opts,
        )

        # Deploy key vault secrets
        keyvault.Secret(
            f"{self._name}_kvs_password_domain_admin",
            properties=keyvault.SecretPropertiesArgs(value=props.password_domain_admin),
            resource_group_name=resource_group.name,
            secret_name="password-domain-admin",
            vault_name=key_vault.name,
            opts=child_opts,
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_domain_azure_ad_connect",
            properties=keyvault.SecretPropertiesArgs(value=props.password_domain_azure_ad_connect),
            resource_group_name=resource_group.name,
            secret_name="password-domain-azure-ad-connect",
            vault_name=key_vault.name,
            opts=child_opts,
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_domain_computer_manager",
            properties=keyvault.SecretPropertiesArgs(value=props.password_domain_computer_manager),
            resource_group_name=resource_group.name,
            secret_name="password-domain-computer-manager",
            vault_name=key_vault.name,
            opts=child_opts,
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_domain_searcher",
            properties=keyvault.SecretPropertiesArgs(value=props.password_domain_searcher),
            resource_group_name=resource_group.name,
            secret_name="password-domain-ldap-searcher",
            vault_name=key_vault.name,
            opts=child_opts,
        )
        keyvault.Secret(
            f"{self._name}_kvs_password_update_server_linux_admin",
            properties=keyvault.SecretPropertiesArgs(value=props.password_update_server_linux_admin),
            resource_group_name=resource_group.name,
            secret_name="password-update-server-linux-admin",
            vault_name=key_vault.name,
            opts=child_opts,
        )

        # Deploy persistent data account
        storage_account_persistent_data = storage.StorageAccount(
            f"{self._name}_storage_account_persistent_data",
            access_tier=storage.AccessTier.COOL,
            # Note that account names have a maximum of 24 characters
            account_name=alphanumeric(f"{''.join(truncate_tokens(stack_name.split('-'), 20))}data")[:24],
            enable_https_traffic_only=True,
            encryption=storage.EncryptionArgs(
                key_source=storage.KeySource.MICROSOFT_STORAGE,
                services=storage.EncryptionServicesArgs(
                    blob=storage.EncryptionServiceArgs(enabled=True, key_type=storage.KeyType.ACCOUNT),
                    file=storage.EncryptionServiceArgs(enabled=True, key_type=storage.KeyType.ACCOUNT),
                ),
            ),
            kind=storage.Kind.STORAGE_V2,
            location=props.location,
            network_rule_set=storage.NetworkRuleSetArgs(
                bypass=storage.Bypass.AZURE_SERVICES,
                default_action=storage.DefaultAction.DENY,
                ip_rules=Output.from_input(props.admin_ip_addresses).apply(
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
        # Deploy staging container for holding any data that does not have an SRE
        storage.BlobContainer(
            f"{self._name}_st_data_staging",
            account_name=storage_account_persistent_data.name,
            container_name=replace_separators(f"{stack_name}-staging", "-")[:63],
            default_encryption_scope="$account-encryption-key",
            deny_encryption_scope_override=False,
            public_access=storage.PublicAccess.NONE,
            resource_group_name=resource_group.name,
            opts=child_opts,
        )

        # Register outputs
        self.password_domain_admin = props.password_domain_admin
        self.password_domain_azure_ad_connect = props.password_domain_azure_ad_connect
        self.password_domain_computer_manager = props.password_domain_computer_manager
        self.password_domain_searcher = props.password_domain_searcher
        self.password_update_server_linux_admin = props.password_update_server_linux_admin
        self.resource_group_name = Output.from_input(resource_group.name)
        self.vault = key_vault
