"""Pulumi component for SHM monitoring"""
from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import (
    automation,
    insights,
    network,
    operationalinsights,
    operationsmanagement,
    resources,
)

from data_safe_haven.functions import (
    ordered_private_dns_zones,
    replace_separators,
    time_as_string,
)
from data_safe_haven.infrastructure.common import get_id_from_subnet
from data_safe_haven.infrastructure.components import WrappedAutomationAccount


class SHMMonitoringProps:
    """Properties for SHMMonitoringComponent"""

    def __init__(
        self,
        dns_resource_group_name: Input[str],
        private_dns_zone_base_id: Input[str],
        location: Input[str],
        subnet_monitoring: Input[network.GetSubnetResult],
        timezone: Input[str],
    ) -> None:
        self.dns_resource_group_name = dns_resource_group_name
        self.private_dns_zone_base_id = private_dns_zone_base_id
        self.location = location
        self.subnet_monitoring_id = Output.from_input(subnet_monitoring).apply(
            get_id_from_subnet
        )
        self.timezone = timezone


class SHMMonitoringComponent(ComponentResource):
    """Deploy SHM monitoring with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SHMMonitoringProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:shm:MonitoringComponent", name, {}, opts)
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

        # Deploy automation account
        automation_account = WrappedAutomationAccount(
            f"{self._name}_automation_account",
            automation_account_name=f"{stack_name}-aa",
            location=props.location,
            name=f"{stack_name}-aa",
            resource_group_name=resource_group.name,
            sku=automation.SkuArgs(name=automation.SkuNameEnum.FREE),
            opts=child_opts,
            tags=child_tags,
        )

        # List of modules as 'name: (version, SHA256 hash)'
        # Note that we exclude ComputerManagementDsc which is already present (https://docs.microsoft.com/en-us/azure/automation/shared-resources/modules#default-modules)
        modules: dict[str, tuple[str, str]] = {
            "ActiveDirectoryDsc": (
                "6.2.0",
                "60b7cc2c578248f23c5b871b093db268a1c1bd89f5ccafc45d9a65c3f0621dca",
            ),
            "PSModulesDsc": (
                "1.0.13.0",
                "b970d3ef7f3694e49993ec434fd166befe493ccaf418b9a79281dda2e230603b",
            ),
            "xPendingReboot": (
                "0.4.0.0",
                "2fbada64b9b1424ee72badf3c332e9670c97e0cc4d20ce4aeb8a499bda2b4d4e",
            ),
            "xPSDesiredStateConfiguration": (
                "9.1.0",
                "1541119e4d47e5f3854d55cff520443b7cefa74842b14932f10dfe0bd820e9c3",
            ),
        }
        for module_name, (module_version, sha256_hash) in modules.items():
            automation.Module(
                f"{self._name}_module_{module_name}".lower(),
                automation_account_name=automation_account.name,
                content_link=automation.ContentLinkArgs(
                    content_hash=automation.ContentHashArgs(
                        algorithm="sha256",
                        value=sha256_hash,
                    ),
                    uri=f"https://www.powershellgallery.com/api/v2/package/{module_name}/{module_version}",
                    version=module_version,
                ),
                module_name=module_name,
                resource_group_name=resource_group.name,
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=automation_account)
                ),
                tags=child_tags,
            )

        # Set up a private endpoint for the automation account
        automation_account_private_endpoint = network.PrivateEndpoint(
            f"{self._name}_automation_account_private_endpoint",
            location=props.location,
            private_endpoint_name=f"{stack_name}-pep-aa",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["DSCAndHybridWorker"],
                    name=f"{stack_name}-cnxn-pep-aa-to-aa",
                    private_link_service_id=automation_account.id,
                )
            ],
            resource_group_name=resource_group.name,
            subnet=network.SubnetArgs(id=props.subnet_monitoring_id),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=automation_account)
            ),
            tags=child_tags,
        )

        # Add a private DNS record for each automation custom DNS config
        automation_account_private_dns = network.PrivateDnsZoneGroup(
            f"{self._name}_automation_account_private_dns_zone_group",
            private_dns_zone_configs=[
                network.PrivateDnsZoneConfigArgs(
                    name=replace_separators(f"{stack_name}-aa-to-{dns_zone_name}", "-"),
                    private_dns_zone_id=Output.concat(
                        props.private_dns_zone_base_id, dns_zone_name
                    ),
                )
                for dns_zone_name in ordered_private_dns_zones("Azure Automation")
            ],
            private_dns_zone_group_name=f"{stack_name}-dzg-aa",
            private_endpoint_name=automation_account_private_endpoint.name,
            resource_group_name=resource_group.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=automation_account_private_endpoint)
            ),
        )

        # Deploy log analytics workspace and get workspace keys
        log_analytics = operationalinsights.Workspace(
            f"{self._name}_log_analytics",
            location=props.location,
            resource_group_name=resource_group.name,
            retention_in_days=30,
            sku=operationalinsights.WorkspaceSkuArgs(
                name=operationalinsights.WorkspaceSkuNameEnum.PER_GB2018,
            ),
            workspace_name=f"{stack_name}-log",
            opts=child_opts,
            tags=child_tags,
        )
        log_analytics_keys = Output.all(
            resource_group_name=resource_group.name, workspace_name=log_analytics.name
        ).apply(lambda kwargs: operationalinsights.get_shared_keys(**kwargs))

        # Set up a private linkscope and endpoint for the log analytics workspace
        log_analytics_private_link_scope = insights.PrivateLinkScope(
            f"{self._name}_log_analytics_private_link_scope",
            location="Global",
            resource_group_name=resource_group.name,
            scope_name=f"{stack_name}-ampls-log",
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=log_analytics)
            ),
            tags=child_tags,
        )
        log_analytics_private_endpoint = network.PrivateEndpoint(
            f"{self._name}_log_analytics_private_endpoint",
            location=props.location,
            private_endpoint_name=f"{stack_name}-pep-log",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["azuremonitor"],
                    name=f"{stack_name}-cnxn-pep-log-to-ampls-log",
                    private_link_service_id=log_analytics_private_link_scope.id,
                )
            ],
            resource_group_name=resource_group.name,
            subnet=network.SubnetArgs(id=props.subnet_monitoring_id),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=log_analytics_private_link_scope)
            ),
            tags=child_tags,
        )
        insights.PrivateLinkScopedResource(
            f"{self._name}_log_analytics_ampls_connection",
            linked_resource_id=log_analytics.id,
            name=f"{stack_name}-cnxn-ampls-log-to-log",
            resource_group_name=resource_group.name,
            scope_name=log_analytics_private_link_scope.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=log_analytics_private_link_scope)
            ),
        )

        # Add a private DNS record for each log analytics workspace custom DNS config
        network.PrivateDnsZoneGroup(
            f"{self._name}_log_analytics_private_dns_zone_group",
            private_dns_zone_configs=[
                network.PrivateDnsZoneConfigArgs(
                    name=replace_separators(
                        f"{stack_name}-log-to-{dns_zone_name}", "-"
                    ),
                    private_dns_zone_id=Output.concat(
                        props.private_dns_zone_base_id, dns_zone_name
                    ),
                )
                for dns_zone_name in ordered_private_dns_zones("Azure Monitor")
            ],
            private_dns_zone_group_name=f"{stack_name}-dzg-log",
            private_endpoint_name=log_analytics_private_endpoint.name,
            resource_group_name=resource_group.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=log_analytics_private_endpoint)
            ),
        )

        # Link automation account to log analytics workspace
        operationalinsights.LinkedService(
            f"{self._name}_automation_log_analytics_link",
            linked_service_name="Automation",
            resource_group_name=resource_group.name,
            resource_id=automation_account.id,
            workspace_name=log_analytics.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=automation_account)
            ),
            tags=child_tags,
        )

        # Deploy log analytics solutions
        solutions = {
            "AgentHealthAssessment": "Agent Health",  # for tracking heartbeats from connected VMs
            "AzureAutomation": "Azure Automation",  # to allow scheduled updating
            "ChangeTracking": "Change Tracking",  # for dashboard of applied changes
            "Updates": "System Update Assessment",  # to assess necessary updates
        }
        for product, description in solutions.items():
            solution_name = Output.concat(product, "(", log_analytics.name, ")")
            operationsmanagement.Solution(
                replace_separators(f"{self._name}_soln_{description.lower()}", "_"),
                location=props.location,
                plan=operationsmanagement.SolutionPlanArgs(
                    name=solution_name,
                    product=f"OMSGallery/{product}",
                    promotion_code="",
                    publisher="Microsoft",
                ),
                properties=operationsmanagement.SolutionPropertiesArgs(
                    workspace_resource_id=log_analytics.id,
                ),
                resource_group_name=resource_group.name,
                solution_name=solution_name,
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=log_analytics)
                ),
                tags=child_tags,
            )

        # Get the current subscription_resource_id for use in scheduling.
        # This is safe as schedules only apply to VMs that are registered with the log analytics workspace
        subscription_resource_id = resource_group.id.apply(
            lambda id_: str(id_).split("/resourceGroups/")[0]
        )
        # Create Windows VM virus definitions update schedule: daily at 01:01
        automation.SoftwareUpdateConfigurationByName(
            f"{self._name}_schedule_windows_definitions",
            automation_account_name=automation_account.name,
            resource_group_name=resource_group.name,
            schedule_info=automation.SUCSchedulePropertiesArgs(
                expiry_time="9999-12-31T23:59:00+00:00",
                frequency="Day",
                interval=1,
                is_enabled=True,
                start_time=Output.from_input(props.timezone).apply(
                    lambda tz: time_as_string(hour=1, minute=1, timezone=tz)
                ),
                time_zone=props.timezone,
            ),
            software_update_configuration_name=f"{stack_name}-windows-definitions",
            update_configuration=automation.UpdateConfigurationArgs(
                operating_system=automation.OperatingSystemType.WINDOWS,
                targets=automation.TargetPropertiesArgs(
                    azure_queries=[
                        automation.AzureQueryPropertiesArgs(
                            locations=[props.location],
                            scope=[subscription_resource_id],
                        )
                    ]
                ),
                windows=automation.WindowsPropertiesArgs(
                    included_update_classifications=automation.WindowsUpdateClasses.DEFINITION,
                    reboot_setting="IfRequired",
                ),
            ),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=["schedule_info"],
                    parent=automation_account,
                ),
            ),
        )
        # Create Windows VM system update schedule: daily at 02:02
        automation.SoftwareUpdateConfigurationByName(
            f"{self._name}_schedule_windows_updates",
            automation_account_name=automation_account.name,
            resource_group_name=resource_group.name,
            schedule_info=automation.SUCSchedulePropertiesArgs(
                expiry_time="9999-12-31T23:59:00+00:00",
                frequency="Day",
                interval=1,
                is_enabled=True,
                start_time=Output.from_input(props.timezone).apply(
                    lambda tz: time_as_string(hour=2, minute=2, timezone=tz)
                ),
                time_zone=props.timezone,
            ),
            software_update_configuration_name=f"{stack_name}-windows-updates",
            update_configuration=automation.UpdateConfigurationArgs(
                azure_virtual_machines=[],
                non_azure_computer_names=[],
                operating_system=automation.OperatingSystemType.WINDOWS,
                targets=automation.TargetPropertiesArgs(
                    azure_queries=[
                        automation.AzureQueryPropertiesArgs(
                            locations=[props.location],
                            scope=[subscription_resource_id],
                        )
                    ]
                ),
                windows=automation.WindowsPropertiesArgs(
                    included_update_classifications=", ".join(
                        [
                            automation.WindowsUpdateClasses.CRITICAL,
                            automation.WindowsUpdateClasses.FEATURE_PACK,
                            automation.WindowsUpdateClasses.SECURITY,
                            automation.WindowsUpdateClasses.SERVICE_PACK,
                            automation.WindowsUpdateClasses.TOOLS,
                            automation.WindowsUpdateClasses.UPDATE_ROLLUP,
                            automation.WindowsUpdateClasses.UPDATES,
                        ]
                    ),
                    reboot_setting="IfRequired",
                ),
            ),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=[
                        "schedule_info",  # options are added after deployment
                        "updateConfiguration.windows.included_package_classifications",  # ordering might change
                    ],
                    parent=automation_account,
                ),
            ),
        )
        # Create Linux VM system update schedule: daily at 02:02
        automation.SoftwareUpdateConfigurationByName(
            f"{self._name}_schedule_linux_updates",
            automation_account_name=automation_account.name,
            resource_group_name=resource_group.name,
            schedule_info=automation.SUCSchedulePropertiesArgs(
                expiry_time="9999-12-31T23:59:00+00:00",
                frequency="Day",
                interval=1,
                is_enabled=True,
                start_time=Output.from_input(props.timezone).apply(
                    lambda tz: time_as_string(hour=2, minute=2, timezone=tz)
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
                            scope=[subscription_resource_id],
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
                    ],
                    parent=automation_account,
                ),
            ),
        )

        # Register outputs
        self.automation_account = automation_account
        self.automation_account_modules = list(modules.keys())
        self.automation_account_private_dns = automation_account_private_dns
        self.log_analytics_workspace = log_analytics
        self.log_analytics_workspace_id = log_analytics.customer_id
        self.log_analytics_workspace_key = Output.secret(
            log_analytics_keys.primary_shared_key
            if log_analytics_keys.primary_shared_key
            else "UNKNOWN"
        )
        self.resource_group_name = resource_group.name

        # Register exports
        self.exports = {
            "automation_account_name": automation_account.name,
            "log_analytics_workspace_id": self.log_analytics_workspace_id,
            "log_analytics_workspace_key": self.log_analytics_workspace_key,
            "resource_group_name": resource_group.name,
        }
