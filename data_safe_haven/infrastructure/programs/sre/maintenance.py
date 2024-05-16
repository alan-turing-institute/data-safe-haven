"""Pulumi component for SRE Maintenance"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import maintenance

from data_safe_haven.functions import next_occurrence


class SREMaintenanceProps:
    """Properties for SREMaintenanceComponent"""

    def __init__(
        self,
        location: Input[str],
        resource_group_name: Input[str],
        timezone: Input[str],
    ) -> None:
        self.location = location
        self.resource_group_name = resource_group_name
        self.timezone = timezone


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
        child_tags = tags if tags else {}

        # Deploy maintenance configuration
        maintenance_configuration = maintenance.MaintenanceConfiguration(
            f"{self._name}_maintenance_configuration",
            duration="03:55",
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
            resource_group_name=props.resource_group_name,
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

        # Register outputs
        self.configuration_id: Output[str] = maintenance_configuration.id
