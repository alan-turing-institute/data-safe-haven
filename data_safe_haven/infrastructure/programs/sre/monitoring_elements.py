from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import maintenance, monitor, operationalinsights

from data_safe_haven.functions import next_occurrence, replace_separators
from data_safe_haven.infrastructure.components import (
    WrappedLogAnalyticsWorkspace,
    WrappedLogAnalyticsWorkspaceProps,
)


class SREMonitoringElementsProps:
    """Properties for SREBasicMonitoringComponent"""

    def __init__(
        self,
        location: Input[str],
        resource_group_name: Input[str],
        timezone: Input[str],
    ) -> None:
        self.location = location
        self.resource_group_name = resource_group_name
        self.timezone = timezone


class SREMonitoringElementsComponent(ComponentResource):

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREMonitoringElementsProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ):
        super().__init__("dsh:sre:MonitoringElementsComponent", name, {}, opts)
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
                    aliases=[
                        f"urn:pulumi:{stack_name}::data-safe-haven::dsh:sre:MonitoringComponent$azure-native:maintenance:MaintenanceConfiguration::sre_monitoring_maintenance_configuration"
                    ],
                    # Ignore start_date_time or this will be changed on each redeploy
                    ignore_changes=["start_date_time"],
                ),
            ),
            tags=child_tags,
        )

        # Deploy log analytics workspace and get workspace keys
        self.log_analytics = WrappedLogAnalyticsWorkspace(
            f"{self._name}_wrapped_log_analytics",
            props=WrappedLogAnalyticsWorkspaceProps(
                location=props.location,
                resource_group_name=props.resource_group_name,
                retention_in_days=30,
                sku=operationalinsights.WorkspaceSkuArgs(
                    name=operationalinsights.WorkspaceSkuNameEnum.PER_GB2018,
                ),
                workspace_name=f"{stack_name}-log-workspace",
            ),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    aliases=[
                        f"urn:pulumi:{stack_name}::data-safe-haven::dsh:sre:MonitoringComponent$azure-native:operationalinsights:Workspace::sre_monitoring_log_analytics"
                    ]
                ),
            ),
            tags=child_tags,
        )

        # Create a data collection endpoint
        self.data_collection_endpoint = monitor.DataCollectionEndpoint(
            f"{self._name}_data_collection_endpoint",
            data_collection_endpoint_name=replace_separators(
                f"{stack_name}-{self._name}-dce", "-"
            )[:44],
            location=props.location,
            network_acls=monitor.DataCollectionEndpointNetworkAclsArgs(
                public_network_access=monitor.KnownPublicNetworkAccessOptions.DISABLED,
            ),
            resource_group_name=props.resource_group_name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    parent=self.log_analytics,
                    delete_before_replace=True,
                    aliases=[
                        f"urn:pulumi:{stack_name}::data-safe-haven::dsh:sre:MonitoringComponent$azure-native:operationalinsights:Workspace$azure-native:monitor:DataCollectionEndpoint::sre_monitoring_data_collection_endpoint"
                    ],
                ),
            ),
            tags=child_tags,
        )

        # Create a data collection rule for VM logs
        self.data_collection_rule_vms = monitor.DataCollectionRule(
            f"{self._name}_data_collection_rule_vms",
            data_collection_rule_name=f"{stack_name}-dcr-vms",
            data_collection_endpoint_id=self.data_collection_endpoint.id,  # used by Logs Ingestion API
            destinations=monitor.DataCollectionRuleDestinationsArgs(
                log_analytics=[
                    monitor.LogAnalyticsDestinationArgs(
                        name=self.log_analytics.name,
                        workspace_resource_id=self.log_analytics.id,
                    )
                ],
            ),
            data_flows=[
                monitor.DataFlowArgs(
                    destinations=[self.log_analytics.name],
                    streams=[
                        monitor.KnownDataFlowStreams.MICROSOFT_PERF,
                    ],
                    transform_kql="source",
                    output_stream=monitor.KnownDataFlowStreams.MICROSOFT_PERF,
                ),
                monitor.DataFlowArgs(
                    destinations=[self.log_analytics.name],
                    streams=[
                        monitor.KnownDataFlowStreams.MICROSOFT_SYSLOG,
                    ],
                    transform_kql="source",
                    output_stream=monitor.KnownDataFlowStreams.MICROSOFT_SYSLOG,
                ),
            ],
            data_sources=monitor.DataCollectionRuleDataSourcesArgs(
                performance_counters=[
                    monitor.PerfCounterDataSourceArgs(
                        counter_specifiers=[
                            "Processor(*)\\% Processor Time",
                            "Memory(*)\\% Used Memory",
                            "Logical Disk(*)\\% Used Space",
                            "System(*)\\Unique Users",
                        ],
                        name="LinuxPerfCounters",
                        sampling_frequency_in_seconds=60,
                        streams=[
                            monitor.KnownPerfCounterDataSourceStreams.MICROSOFT_PERF,
                        ],
                    ),
                ],
                syslog=[
                    monitor.SyslogDataSourceArgs(
                        facility_names=[
                            # Note that ASTERISK is not currently working
                            monitor.KnownSyslogDataSourceFacilityNames.ALERT,
                            monitor.KnownSyslogDataSourceFacilityNames.AUDIT,
                            monitor.KnownSyslogDataSourceFacilityNames.AUTH,
                            monitor.KnownSyslogDataSourceFacilityNames.AUTHPRIV,
                            monitor.KnownSyslogDataSourceFacilityNames.CLOCK,
                            monitor.KnownSyslogDataSourceFacilityNames.CRON,
                            monitor.KnownSyslogDataSourceFacilityNames.DAEMON,
                            monitor.KnownSyslogDataSourceFacilityNames.FTP,
                            monitor.KnownSyslogDataSourceFacilityNames.KERN,
                            monitor.KnownSyslogDataSourceFacilityNames.LPR,
                            monitor.KnownSyslogDataSourceFacilityNames.MAIL,
                            monitor.KnownSyslogDataSourceFacilityNames.MARK,
                            monitor.KnownSyslogDataSourceFacilityNames.NEWS,
                            monitor.KnownSyslogDataSourceFacilityNames.NOPRI,
                            monitor.KnownSyslogDataSourceFacilityNames.NTP,
                            monitor.KnownSyslogDataSourceFacilityNames.SYSLOG,
                            monitor.KnownSyslogDataSourceFacilityNames.USER,
                            monitor.KnownSyslogDataSourceFacilityNames.UUCP,
                        ],
                        log_levels=[
                            # Note that ASTERISK is not currently working
                            monitor.KnownSyslogDataSourceLogLevels.DEBUG,
                            monitor.KnownSyslogDataSourceLogLevels.INFO,
                            monitor.KnownSyslogDataSourceLogLevels.NOTICE,
                            monitor.KnownSyslogDataSourceLogLevels.WARNING,
                            monitor.KnownSyslogDataSourceLogLevels.ERROR,
                            monitor.KnownSyslogDataSourceLogLevels.CRITICAL,
                            monitor.KnownSyslogDataSourceLogLevels.ALERT,
                            monitor.KnownSyslogDataSourceLogLevels.EMERGENCY,
                        ],
                        name="LinuxSyslog",
                        streams=[monitor.KnownSyslogDataSourceStreams.MICROSOFT_SYSLOG],
                    ),
                ],
            ),
            location=props.location,
            resource_group_name=props.resource_group_name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    parent=self.log_analytics,
                    aliases=[
                        f"urn:pulumi:{stack_name}::data-safe-haven::dsh:sre:MonitoringComponent$azure-native:operationalinsights:Workspace$azure-native:monitor:DataCollectionRule::sre_monitoring_data_collection_rule_vms",
                        f"urn:pulumi:{stack_name}::data-safe-haven::dsh:sre:MonitoringElementsComponent$azure-native:operationalinsights:Workspace$azure-native:monitor:DataCollectionRule::sre_monitoring_elements_data_collection_rule_vms",
                    ],
                    delete_before_replace=True,
                ),
            ),
            tags=child_tags,
        )
