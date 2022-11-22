"""Pulumi component for SHM state"""
# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import keyvault, resources


class SHMStateProps:
    """Properties for SHMStateComponent"""

    def __init__(
        self,
        admin_group_id: Input[str],
        location: Input[str],
        tenant_id: Input[str],
    ):
        self.admin_group_id = admin_group_id
        self.location = location
        self.tenant_id = tenant_id


class SHMStateComponent(ComponentResource):
    """Deploy SHM state with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        shm_name: str,
        props: SHMStateProps,
        opts: ResourceOptions = None,
    ):
        super().__init__("dsh:shm:SHMStateComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"rg-{stack_name}-state",
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
            vault_name=f"kv-{stack_name[:15]}-state",  # maximum of 24 characters
        )
        # Register outputs
        self.resource_group_name = Output.from_input(resource_group.name)
        self.vault = key_vault
