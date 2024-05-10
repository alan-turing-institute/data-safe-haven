"""Pulumi component for SRE Maintenance"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, ResourceOptions
from pulumi_azure_native import dataprotection, resources


class SREMaintenanceProps:
    """Properties for SREMaintenanceComponent"""

    def __init__(
        self,
        location: Input[str],
    ) -> None:
        self.location = location


class SREMaintenanceComponent(ComponentResource):
    """Deploy SRE maintenance with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREMaintenanceProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:MaintenanceComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-maintenance",
            opts=child_opts,
            tags=child_tags,
        )
