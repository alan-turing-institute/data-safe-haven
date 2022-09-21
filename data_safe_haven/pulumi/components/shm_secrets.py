# Standard library imports
from typing import Optional, Sequence

# Third party imports
from pulumi import ComponentResource, Input, ResourceOptions, Output
from pulumi_azure_native import keyvault
from data_safe_haven.helpers import AzureIPv4Range


class SHMSecretsProps:
    """Properties for SHMSecretsComponent"""

    def __init__(
        self,
        admin_group_id: Input[str],
        location: Input[str],
        resource_group_name: Input[str],
        tenant_id: Input[str],
    ):
        self.admin_group_id = admin_group_id
        self.location = location
        self.resource_group_name = resource_group_name
        self.tenant_id = tenant_id


class SHMSecretsComponent(ComponentResource):
    """Deploy SHM secrets with Pulumi"""

    def __init__(self, name: str, props: SHMSecretsProps, opts: ResourceOptions = None):
        super().__init__("dsh:shm_secrets:SHMSecretsComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Define SHM KeyVault
        vault = keyvault.Vault(
            "vault",
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
            resource_group_name=props.resource_group_name,
            vault_name=f"kv-{self._name[:13]}-secrets",  # maximum of 24 characters
        )
        # Register outputs
        self.resource_group_name = Output.from_input(props.resource_group_name)
        self.vault = vault
