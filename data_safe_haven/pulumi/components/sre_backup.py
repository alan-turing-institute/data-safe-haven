"""Pulumi component for SRE state"""
from pulumi import ComponentResource, Input, ResourceOptions
from pulumi_azure_native import dataprotection, resources


class SREBackupProps:
    """Properties for SREBackupComponent"""

    def __init__(
        self,
        location: Input[str],
    ) -> None:
        self.location = location


class SREBackupComponent(ComponentResource):
    """Deploy SRE backup with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREBackupProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:BackupComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-backup",
            opts=child_opts,
        )

        # Deploy backup vault
        dataprotection.BackupVault(
            f"{self._name}_backup_vault",
            identity=dataprotection.DppIdentityDetailsArgs(
                type="SystemAssigned",
            ),
            location=props.location,
            properties=dataprotection.BackupVaultArgs(
                storage_settings=[
                    dataprotection.StorageSettingArgs(
                        datastore_type=dataprotection.StorageSettingStoreTypes.VAULT_STORE,
                        type=dataprotection.StorageSettingTypes.LOCALLY_REDUNDANT,
                    )
                ],
            ),
            resource_group_name=resource_group.name,
            vault_name=f"{stack_name}-bv-backup",
        )
