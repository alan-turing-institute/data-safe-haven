"""Pulumi component for SRE monitoring"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import maintenance, resources

from data_safe_haven.functions import next_occurrence


class SREMonitoringProps:
    """Properties for SREMonitoringComponent"""

    def __init__(
        self,
        location: Input[str],
        timezone: Input[str],
    ) -> None:
        self.location = location
        self.timezone = timezone


class SREMonitoringComponent(ComponentResource):
    """Deploy SRE monitoring with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREMonitoringProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:MonitoringComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-monitoring",
            opts=child_opts,
            tags=child_tags,
        )

        # Deploy maintenance configuration
        # See https://learn.microsoft.com/en-us/azure/update-manager/scheduled-patching
        self.maintenance_configuration = maintenance.MaintenanceConfiguration(
            f"{self._name}_maintenance_configuration",
            duration="03:55",  # Maximum allowed value for this parameter
            extension_properties={"InGuestPatchMode": "User"},
            install_patches=maintenance.InputPatchConfigurationArgs(
                linux_parameters=maintenance.InputLinuxParametersArgs(
                    classifications_to_include=["Critical", "Security"],
                ),
                reboot_setting="IfRequired",
            ),
            location=props.location,
            maintenance_scope=maintenance.MaintenanceScope.IN_GUEST_PATCH,
            recur_every="1Day",
            resource_group_name=resource_group.name,
            resource_name_=f"{stack_name}-maintenance-configuration",
            start_date_time=Output.from_input(props.timezone).apply(
                lambda timezone: next_occurrence(
                    hour=2,
                    minute=4,
                    timezone=timezone,
                    time_format="iso_minute",
                )  # Run maintenance at 02:04 local time every night
            ),
            time_zone="UTC",  # Our start time is given in UTC
            visibility=maintenance.Visibility.CUSTOM,
            tags=child_tags,
        )
