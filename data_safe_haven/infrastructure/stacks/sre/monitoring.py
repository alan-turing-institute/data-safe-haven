"""Pulumi component for SHM monitoring"""
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import automation

from data_safe_haven.functions import time_as_string


class SREMonitoringProps:
    """Properties for SREMonitoringComponent"""

    def __init__(
        self,
        automation_account_name: Input[str],
        resource_group_name: Input[str],
        location: Input[str],
        sre_index: Input[int],
        subscription_resource_id: Input[str],
        timezone: Input[str],
    ) -> None:
        self.automation_account_name = automation_account_name
        self.location = location
        self.resource_group_name = resource_group_name
        self.subscription_resource_id = subscription_resource_id
        self.sre_index = sre_index
        self.timezone = timezone


class SREMonitoringComponent(ComponentResource):
    """Deploy SHM monitoring with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREMonitoringProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:MonitoringComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        # Create Linux VM system update schedule: daily at 03:<index>
        automation.SoftwareUpdateConfigurationByName(
            f"{self._name}_schedule_linux_updates",
            automation_account_name=props.automation_account_name,
            resource_group_name=props.resource_group_name,
            schedule_info=automation.SUCSchedulePropertiesArgs(
                expiry_time="9999-12-31T23:59:00+00:00",
                frequency="Day",
                interval=1,
                is_enabled=True,
                start_time=Output.all(
                    timezone=props.timezone, minute=props.sre_index
                ).apply(
                    lambda kwargs: time_as_string(
                        hour=3,
                        minute=int(kwargs["minute"]),
                        timezone=str(kwargs["timezone"]),
                    )
                ),
                time_zone=props.timezone,
            ),
            software_update_configuration_name=f"{stack_name}-linux-updates",
            update_configuration=automation.UpdateConfigurationArgs(
                azure_virtual_machines=[],
                linux=automation.LinuxPropertiesArgs(
                    included_package_classifications=", ".join(
                        [
                            automation.LinuxUpdateClasses.CRITICAL,
                            automation.LinuxUpdateClasses.OTHER,
                            automation.LinuxUpdateClasses.SECURITY,
                            automation.LinuxUpdateClasses.UNCLASSIFIED,
                        ]
                    ),
                    reboot_setting="IfRequired",
                ),
                non_azure_computer_names=[],
                operating_system=automation.OperatingSystemType.LINUX,
                targets=automation.TargetPropertiesArgs(
                    azure_queries=[
                        automation.AzureQueryPropertiesArgs(
                            locations=[props.location],
                            scope=[props.subscription_resource_id],
                        )
                    ]
                ),
            ),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=[
                        "schedule_info",  # options are added after deployment
                        "updateConfiguration.linux.included_package_classifications",  # ordering might change
                    ]
                ),
            ),
        )
