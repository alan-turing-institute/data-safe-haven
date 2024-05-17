"""Pulumi component for SHM monitoring"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import (
    insights,
    network,
    operationalinsights,
    operationsmanagement,
    resources,
)

from data_safe_haven.functions import (
    replace_separators,
)
from data_safe_haven.infrastructure.common import get_id_from_subnet
from data_safe_haven.infrastructure.components import (
    WrappedLogAnalyticsWorkspace,
)
from data_safe_haven.types import AzureDnsZoneNames


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

        # Deploy log analytics workspace and get workspace keys
        log_analytics = WrappedLogAnalyticsWorkspace(
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
            "ChangeTracking": "Change Tracking",  # for dashboard of applied changes
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

        # Register outputs
        self.log_analytics_workspace = log_analytics
        self.resource_group_name = resource_group.name

        # Register exports
        self.exports = {
            "log_analytics_workspace_id": self.log_analytics_workspace.workspace_id,
            "log_analytics_workspace_key": self.log_analytics_workspace.workspace_key,
            "resource_group_name": resource_group.name,
        }
