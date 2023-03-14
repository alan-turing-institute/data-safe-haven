"""Pulumi component for SHM state"""
# Standard library imports
from typing import Optional

# Third party imports
from pulumi import Config, ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import keyvault, resources


class SHMStateProps:
    """Properties for SHMStateComponent"""

    def __init__(
        self,
        admin_group_id: Input[str],
        location: Input[str],
        pulumi_opts: Config,
        tenant_id: Input[str],
    ):
        self.admin_group_id = admin_group_id
        self.location = location
        self.password_domain_admin = self.get_secret(
            pulumi_opts, "password-domain-admin"
        )
        self.password_domain_azure_ad_connect = self.get_secret(
            pulumi_opts, "password-domain-azure-ad-connect"
        )
        self.password_domain_computer_manager = self.get_secret(
            pulumi_opts, "password-domain-computer-manager"
        )
        self.password_domain_searcher = self.get_secret(
            pulumi_opts, "password-domain-ldap-searcher"
        )
        self.password_update_server_linux_admin = self.get_secret(
            pulumi_opts, "password-update-server-linux-admin"
        )
        self.tenant_id = tenant_id

    def get_secret(self, pulumi_opts: Config, secret_name: str) -> Output[str]:
        return Output.secret(pulumi_opts.require(secret_name))


class SHMStateComponent(ComponentResource):
    """Deploy SHM state with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        shm_name: str,
        props: SHMStateProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:shm:SHMStateComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-state",
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
            vault_name=f"{stack_name[:15]}-kv-state",  # maximum of 24 characters
            opts=child_opts,
        )

        # Deploy key vault secrets
        password_domain_admin = keyvault.Secret(
            f"{self._name}_kvs_password_domain_admin",
            properties=keyvault.SecretPropertiesArgs(value=props.password_domain_admin),
            resource_group_name=resource_group.name,
            secret_name="password-domain-admin",
            vault_name=key_vault.name,
            opts=child_opts,
        )
        password_domain_azure_ad_connect = keyvault.Secret(
            f"{self._name}_kvs_password_domain_azure_ad_connect",
            properties=keyvault.SecretPropertiesArgs(
                value=props.password_domain_azure_ad_connect
            ),
            resource_group_name=resource_group.name,
            secret_name="password-domain-azure-ad-connect",
            vault_name=key_vault.name,
            opts=child_opts,
        )
        password_domain_computer_manager = keyvault.Secret(
            f"{self._name}_kvs_password_domain_computer_manager",
            properties=keyvault.SecretPropertiesArgs(
                value=props.password_domain_computer_manager
            ),
            resource_group_name=resource_group.name,
            secret_name="password-domain-computer-manager",
            vault_name=key_vault.name,
            opts=child_opts,
        )
        password_domain_searcher = keyvault.Secret(
            f"{self._name}_kvs_password_domain_searcher",
            properties=keyvault.SecretPropertiesArgs(
                value=props.password_domain_searcher
            ),
            resource_group_name=resource_group.name,
            secret_name="password-domain-ldap-searcher",
            vault_name=key_vault.name,
            opts=child_opts,
        )
        password_update_server_linux_admin = keyvault.Secret(
            f"{self._name}_kvs_password_update_server_linux_admin",
            properties=keyvault.SecretPropertiesArgs(
                value=props.password_update_server_linux_admin
            ),
            resource_group_name=resource_group.name,
            secret_name="password-update-server-linux-admin",
            vault_name=key_vault.name,
            opts=child_opts,
        )

        # Register outputs
        self.password_domain_admin = props.password_domain_admin
        self.password_domain_azure_ad_connect = props.password_domain_azure_ad_connect
        self.password_domain_computer_manager = props.password_domain_computer_manager
        self.password_domain_searcher = props.password_domain_searcher
        self.password_update_server_linux_admin = (
            props.password_update_server_linux_admin
        )
        self.resource_group_name = Output.from_input(resource_group.name)
        self.vault = key_vault
