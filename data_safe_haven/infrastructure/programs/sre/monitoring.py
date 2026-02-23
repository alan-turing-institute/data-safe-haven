"""Pulumi component for SRE monitoring"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import monitor, network, operationalinsights, privatedns

from data_safe_haven.functions import replace_separators
from data_safe_haven.infrastructure.common import get_id_from_subnet
from data_safe_haven.types import AzureDnsZoneNames


class SREMonitoringNetworkingProps:
    """Properties for SREMonitoringComponent"""

    def __init__(
        self,
        data_collection_endpoint_id: Input[str],
        dns_private_zones: Input[dict[str, privatedns.PrivateZone]],
        location: Input[str],
        log_analytics: operationalinsights.Workspace,
        resource_group_name: Input[str],
        subnet: Input[network.GetSubnetResult],
        timezone: Input[str],
    ) -> None:
        self.data_collection_endpoint_id = data_collection_endpoint_id
        self.dns_private_zones = dns_private_zones
        self.location = location
        self.log_analytics = log_analytics
        self.resource_group_name = resource_group_name
        self.subnet_id = Output.from_input(subnet).apply(get_id_from_subnet)
        self.timezone = timezone


class SREMonitoringComponent(ComponentResource):
    """Deploy SRE monitoring with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREMonitoringNetworkingProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:MonitoringComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "monitoring"} | (tags if tags else {})

        # Create a private linkscope
        log_analytics_private_link_scope = monitor.PrivateLinkScope(
            f"{self._name}_log_analytics_private_link_scope",
            access_mode_settings=monitor.AccessModeSettingsArgs(
                ingestion_access_mode=monitor.AccessMode.PRIVATE_ONLY,
                query_access_mode=monitor.AccessMode.PRIVATE_ONLY,
            ),
            location="Global",
            resource_group_name=props.resource_group_name,
            scope_name=f"{stack_name}-ampls",
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    parent=props.log_analytics,
                    delete_before_replace=True,
                    aliases=[
                        f"urn:pulumi:{stack_name}::data-safe-haven::dsh:sre:MonitoringElementsComponent$azure-native:operationalinsights:Workspace$azure-native:monitor:PrivateLinkScope::sre_monitoring_log_analytics_private_link_scope"
                    ],
                ),
            ),
            tags=child_tags,
        )
        # Link the private linkscope to the log analytics workspace
        monitor.PrivateLinkScopedResource(
            f"{self._name}_log_analytics_ampls_connection",
            kind=monitor.ScopedResourceKind.RESOURCE,
            linked_resource_id=props.log_analytics.id,
            name=f"{stack_name}-cnxn-ampls-to-log-analytics",
            resource_group_name=props.resource_group_name,
            scope_name=log_analytics_private_link_scope.name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    parent=log_analytics_private_link_scope, delete_before_replace=True
                ),
            ),
        )

        # Create a private endpoint for the log analytics workspace
        log_analytics_private_endpoint = network.PrivateEndpoint(
            f"{self._name}_log_analytics_private_endpoint",
            custom_network_interface_name=f"{stack_name}-pep-log-analytics-nic",
            location=props.location,
            private_endpoint_name=f"{stack_name}-pep-log-analytics",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["azuremonitor"],
                    name=f"{stack_name}-cnxn-ampls-to-pep-log-analytics",
                    private_link_service_id=log_analytics_private_link_scope.id,
                )
            ],
            resource_group_name=props.resource_group_name,
            subnet=network.SubnetArgs(id=props.subnet_id),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    depends_on=[log_analytics_private_link_scope, props.log_analytics],
                    ignore_changes=["custom_dns_configs"],
                    parent=props.log_analytics,
                ),
            ),
            tags=child_tags,
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
            resource_group_name=props.resource_group_name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    depends_on=log_analytics_private_endpoint,
                    parent=log_analytics_private_endpoint,
                ),
            ),
        )

        # Link the private linkscope to the data collection endpoint
        monitor.PrivateLinkScopedResource(
            f"{self._name}_data_collection_endpoint_ampls_connection",
            kind=monitor.ScopedResourceKind.RESOURCE,
            linked_resource_id=props.data_collection_endpoint_id,
            name=f"{stack_name}-cnxn-ampls-to-dce",
            resource_group_name=props.resource_group_name,
            scope_name=log_analytics_private_link_scope.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=log_analytics_private_link_scope)
            ),
        )
