"""Pulumi component for SRE state"""
from pulumi import ComponentResource, Input, ResourceOptions
from pulumi_azure_native import resources


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
        resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-backup",
            opts=child_opts,
        )
