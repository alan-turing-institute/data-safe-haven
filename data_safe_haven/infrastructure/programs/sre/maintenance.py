"""Pulumi component for SRE Maintenance"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, ResourceOptions
from pulumi_azure_native import resources, maintenance


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

        maintenance_configuration = maintenance.MaintenanceConfiguration(
            f"{self._name}_maintenance_configuration",
            duration="03:55",
            #expiration_date_time="9999-12-31 00:00",
            extension_properties={"InGuestPatchMode": "User"},
            install_patches=maintenance.InputPatchConfigurationArgs(
                linux_parameters=maintenance.InputLinuxParametersArgs(
                    classifications_to_include=["Critical", "Security"],
                ),
                reboot_setting="IfRequired",
            ),
            location=props.location,
            maintenance_scope=maintenance.MaintenanceScope.IN_GUEST_PATCH,
            #namespace="Microsoft.Maintenance",
            recur_every="1Day",
            resource_group_name=resource_group.name,
            resource_name_=f"{stack_name}-maintenance-configuration",
            start_date_time="2020-04-30 01:00",
            time_zone="GMT Standard Time",
            visibility=maintenance.Visibility.CUSTOM)
