"""Pulumi component for SRE monitoring"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import insights, maintenance, network, operationalinsights

from data_safe_haven.functions import next_occurrence, replace_separators
from data_safe_haven.infrastructure.common import get_id_from_subnet
from data_safe_haven.infrastructure.components import WrappedLogAnalyticsWorkspace
from data_safe_haven.types import AzureDnsZoneNames


class SREMonitoringProps:
    """Properties for SREMonitoringComponent"""

    def __init__(
        self,
        dns_private_zones: Input[dict[str, network.PrivateZone]],
        location: Input[str],
        resource_group_name: Input[str],
        subnet: Input[network.GetSubnetResult],
        timezone: Input[str],
    ) -> None:
        self.dns_private_zones = dns_private_zones
        self.location = location
        self.resource_group_name = resource_group_name
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
        child_tags = {"component": "monitoring"} | (tags if tags else {})

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
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    # Ignore start_date_time or this will be changed on each redeploy
                    ignore_changes=["start_date_time"]
                ),
            ),
            tags=child_tags,
        )

        # Deploy log analytics workspace and get workspace keys
        self.log_analytics = WrappedLogAnalyticsWorkspace(
            f"{self._name}_log_analytics",
            location=props.location,
            resource_group_name=props.resource_group_name,
            retention_in_days=30,
            sku=operationalinsights.WorkspaceSkuArgs(
                name=operationalinsights.WorkspaceSkuNameEnum.PER_GB2018,
            ),
            workspace_name=f"{stack_name}-log",
            opts=child_opts,
            tags=child_tags,
        )

        # Create a private linkscope
        log_analytics_private_link_scope = insights.PrivateLinkScope(
            f"{self._name}_log_analytics_private_link_scope",
            access_mode_settings=insights.AccessModeSettingsArgs(
                ingestion_access_mode=insights.AccessMode.PRIVATE_ONLY,
                query_access_mode=insights.AccessMode.PRIVATE_ONLY,
            ),
            location="Global",
            resource_group_name=props.resource_group_name,
            scope_name=f"{stack_name}-ampls",
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    parent=self.log_analytics,
                ),
            ),
            tags=child_tags,
        )
        # Link the private linkscope to the log analytics workspace
        insights.PrivateLinkScopedResource(
            f"{self._name}_log_analytics_ampls_connection",
            linked_resource_id=self.log_analytics.id,
            name=f"{stack_name}-cnxn-ampls-to-log-analytics",
            resource_group_name=props.resource_group_name,
            scope_name=log_analytics_private_link_scope.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=log_analytics_private_link_scope)
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
                    depends_on=[log_analytics_private_link_scope, self.log_analytics],
                    ignore_changes=["custom_dns_configs"],
                    parent=self.log_analytics,
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

        # Create a data collection endpoint
        self.data_collection_endpoint = insights.DataCollectionEndpoint(
            f"{self._name}_data_collection_endpoint",
            data_collection_endpoint_name=f"{stack_name}-dce",
            location=props.location,
            network_acls=insights.DataCollectionEndpointNetworkAclsArgs(
                public_network_access=insights.KnownPublicNetworkAccessOptions.DISABLED,
            ),
            resource_group_name=props.resource_group_name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=self.log_analytics),
            ),
            tags=child_tags,
        )
        # Link the private linkscope to the data collection endpoint
        insights.PrivateLinkScopedResource(
            f"{self._name}_data_collection_endpoint_ampls_connection",
            linked_resource_id=self.data_collection_endpoint.id,
            name=f"{stack_name}-cnxn-ampls-to-dce",
            resource_group_name=props.resource_group_name,
            scope_name=log_analytics_private_link_scope.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=log_analytics_private_link_scope)
            ),
        )

        # Create a data collection rule for VM logs
        self.data_collection_rule_vms = insights.DataCollectionRule(
            f"{self._name}_data_collection_rule_vms",
            data_collection_rule_name=f"{stack_name}-dcr-vms",
            data_collection_endpoint_id=self.data_collection_endpoint.id,  # used by Logs Ingestion API
            destinations=insights.DataCollectionRuleDestinationsArgs(
                log_analytics=[
                    insights.LogAnalyticsDestinationArgs(
                        name=self.log_analytics.name,
                        workspace_resource_id=self.log_analytics.id,
                    )
                ],
            ),
            data_flows=[
                insights.DataFlowArgs(
                    destinations=[self.log_analytics.name],
                    streams=[
                        insights.KnownDataFlowStreams.MICROSOFT_PERF,
                    ],
                    transform_kql="source",
                    output_stream=insights.KnownDataFlowStreams.MICROSOFT_PERF,
                ),
                insights.DataFlowArgs(
                    destinations=[self.log_analytics.name],
                    streams=[
                        insights.KnownDataFlowStreams.MICROSOFT_SYSLOG,
                    ],
                    transform_kql="source",
                    output_stream=insights.KnownDataFlowStreams.MICROSOFT_SYSLOG,
                ),
            ],
            data_sources=insights.DataCollectionRuleDataSourcesArgs(
                performance_counters=[
                    insights.PerfCounterDataSourceArgs(
                        counter_specifiers=[
                            "Processor(*)\\% Processor Time",
                            "Memory(*)\\% Used Memory",
                            "Logical Disk(*)\\% Used Space",
                            "System(*)\\Unique Users",
                        ],
                        name="LinuxPerfCounters",
                        sampling_frequency_in_seconds=60,
                        streams=[
                            insights.KnownPerfCounterDataSourceStreams.MICROSOFT_PERF,
                        ],
                    ),
                ],
                syslog=[
                    insights.SyslogDataSourceArgs(
                        facility_names=[
                            # Note that ASTERISK is not currently working
                            insights.KnownSyslogDataSourceFacilityNames.ALERT,
                            insights.KnownSyslogDataSourceFacilityNames.AUDIT,
                            insights.KnownSyslogDataSourceFacilityNames.AUTH,
                            insights.KnownSyslogDataSourceFacilityNames.AUTHPRIV,
                            insights.KnownSyslogDataSourceFacilityNames.CLOCK,
                            insights.KnownSyslogDataSourceFacilityNames.CRON,
                            insights.KnownSyslogDataSourceFacilityNames.DAEMON,
                            insights.KnownSyslogDataSourceFacilityNames.FTP,
                            insights.KnownSyslogDataSourceFacilityNames.KERN,
                            insights.KnownSyslogDataSourceFacilityNames.LPR,
                            insights.KnownSyslogDataSourceFacilityNames.MAIL,
                            insights.KnownSyslogDataSourceFacilityNames.MARK,
                            insights.KnownSyslogDataSourceFacilityNames.NEWS,
                            insights.KnownSyslogDataSourceFacilityNames.NOPRI,
                            insights.KnownSyslogDataSourceFacilityNames.NTP,
                            insights.KnownSyslogDataSourceFacilityNames.SYSLOG,
                            insights.KnownSyslogDataSourceFacilityNames.USER,
                            insights.KnownSyslogDataSourceFacilityNames.UUCP,
                        ],
                        log_levels=[
                            # Note that ASTERISK is not currently working
                            insights.KnownSyslogDataSourceLogLevels.DEBUG,
                            insights.KnownSyslogDataSourceLogLevels.INFO,
                            insights.KnownSyslogDataSourceLogLevels.NOTICE,
                            insights.KnownSyslogDataSourceLogLevels.WARNING,
                            insights.KnownSyslogDataSourceLogLevels.ERROR,
                            insights.KnownSyslogDataSourceLogLevels.CRITICAL,
                            insights.KnownSyslogDataSourceLogLevels.ALERT,
                            insights.KnownSyslogDataSourceLogLevels.EMERGENCY,
                        ],
                        name="LinuxSyslog",
                        streams=[
                            insights.KnownSyslogDataSourceStreams.MICROSOFT_SYSLOG
                        ],
                    ),
                ],
            ),
            location=props.location,
            resource_group_name=props.resource_group_name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=self.log_analytics),
            ),
            tags=child_tags,
        )
