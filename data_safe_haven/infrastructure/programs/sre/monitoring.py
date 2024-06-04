"""Pulumi component for SRE monitoring"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import (
    insights,
    maintenance,
    network,
    operationalinsights,
    operationsmanagement,
    resources,
)

from data_safe_haven.functions import next_occurrence, replace_separators
from data_safe_haven.infrastructure.common import get_id_from_subnet
from data_safe_haven.infrastructure.components import (
    WrappedLogAnalyticsWorkspace,
)
from data_safe_haven.types import AzureDnsZoneNames


class SREMonitoringProps:
    """Properties for SREMonitoringComponent"""

    def __init__(
        self,
        dns_private_zones: Input[dict[str, network.PrivateZone]],
        location: Input[str],
        subnet: Input[network.GetSubnetResult],
        timezone: Input[str],
    ) -> None:
        self.dns_private_zones = dns_private_zones
        self.location = location
        self.subnet_id = Output.from_input(subnet).apply(get_id_from_subnet)
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

        # Deploy log analytics workspace and get workspace keys
        self.log_analytics = WrappedLogAnalyticsWorkspace(
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

        # Set up a private linkscope and endpoint for the log analytics workspace
        log_analytics_private_link_scope = insights.PrivateLinkScope(
            f"{self._name}_log_analytics_private_link_scope",
            access_mode_settings=insights.AccessModeSettingsArgs(
                ingestion_access_mode=insights.AccessMode.PRIVATE_ONLY,
                query_access_mode=insights.AccessMode.PRIVATE_ONLY,
            ),
            location="Global",
            resource_group_name=resource_group.name,
            scope_name=f"{stack_name}-ampls-log",
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    depends_on=self.log_analytics,
                    parent=self.log_analytics,
                ),
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
            subnet=network.SubnetArgs(id=props.subnet_id),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=["custom_dns_configs"],
                    parent=log_analytics_private_link_scope,
                ),
            ),
            tags=child_tags,
        )
        insights.PrivateLinkScopedResource(
            f"{self._name}_log_analytics_ampls_connection",
            linked_resource_id=self.log_analytics.id,
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
                    private_dns_zone_id=props.dns_private_zones[dns_zone_name].id,
                )
                for dns_zone_name in AzureDnsZoneNames.AZURE_MONITOR
            ],
            private_dns_zone_group_name=f"{stack_name}-dzg-log",
            private_endpoint_name=log_analytics_private_endpoint.name,
            resource_group_name=resource_group.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=log_analytics_private_endpoint)
            ),
        )

        # Deploy log analytics solutions
        solutions = {
            "AgentHealthAssessment": "Agent Health",  # for tracking heartbeats from connected VMs
        }
        for product, description in solutions.items():
            solution_name = Output.concat(product, "(", self.log_analytics.name, ")")
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
                    workspace_resource_id=self.log_analytics.id,
                ),
                resource_group_name=resource_group.name,
                solution_name=solution_name,
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=self.log_analytics)
                ),
                tags=child_tags,
            )
