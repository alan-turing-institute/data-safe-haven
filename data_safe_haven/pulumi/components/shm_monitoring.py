"""Pulumi component for SHM monitoring"""
# Standard library import
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import (
    automation,
    insights,
    network,
    operationalinsights,
    resources,
)

# Local imports
from data_safe_haven.pulumi.transformations import get_id_from_subnet


class SHMMonitoringProps:
    """Properties for SHMMonitoringComponent"""

    def __init__(
        self,
        dns_resource_group_name: Input[str],
        location: Input[str],
        subnet_monitoring: Input[network.GetSubnetResult],
    ) -> None:
        self.dns_resource_group_name = dns_resource_group_name
        self.location = location
        self.subnet_monitoring_id = Output.from_input(subnet_monitoring).apply(
            get_id_from_subnet
        )


class SHMMonitoringComponent(ComponentResource):
    """Deploy SHM monitoring with Pulumi"""

    private_zone_names = [
        "agentsvc.azure-automation.net",
        "azure-automation.net",
        "blob.core.windows.net",
        "monitor.azure.com",
    ]

    def __init__(
        self,
        name: str,
        stack_name: str,
        shm_name: str,
        props: SHMMonitoringProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:shm:SHMMonitoringComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-monitoring",
            opts=child_opts,
        )

        # Deploy automation account
        automation_account = automation.AutomationAccount(
            f"{self._name}_automationAccount",
            automation_account_name=f"{stack_name}-automation",
            location=props.location,
            name=f"{stack_name}-automation",
            resource_group_name=resource_group.name,
            sku=automation.SkuArgs(name="Free"),
            opts=child_opts,
        )
        automation_keys = automation.list_key_by_automation_account(
            automation_account.name, resource_group_name=resource_group.name
        )

        # List of modules as 'name: (version, SHA256 hash)'
        # Note that we exclude ComputerManagementDsc which is already present (https://docs.microsoft.com/en-us/azure/automation/shared-resources/modules#default-modules)
        modules = {
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
            module = automation.Module(
                f"{self._name}_module_{module_name}",
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
                opts=child_opts,
            )

        # Set up a private endpoint for the automation account
        automation_private_endpoint = network.PrivateEndpoint(
            f"{self._name}_automation_private_endpoint",
            location=props.location,
            private_endpoint_name=f"{stack_name}-automation-pep",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["DSCAndHybridWorker"],
                    name="DSCAndHybridWorker",
                    private_link_service_id=automation_account.id,
                    request_message="Connection auto-approved.",
                )
            ],
            resource_group_name=resource_group.name,
            subnet=network.SubnetArgs(id=props.subnet_monitoring_id),
            opts=child_opts,
        )

        # Add a private DNS record for each automation custom DNS config
        automation_private_endpoint.custom_dns_configs.apply(
            lambda cfgs: [
                self.private_record_set(cfg, props.dns_resource_group_name, child_opts)
                for cfg in cfgs
            ]
            if cfgs
            else []
        )

        # Deploy log analytics workspace
        workspace = operationalinsights.Workspace(
            f"{self._name}_log_analytics_workspace",
            location=props.location,
            resource_group_name=resource_group.name,
            retention_in_days=30,
            sku=operationalinsights.WorkspaceSkuArgs(
                name=operationalinsights.WorkspaceSkuNameEnum.PER_GB2018,
            ),
            workspace_name=f"{stack_name}-log",
            opts=child_opts,
        )

        # Set up a private linkscope and endpoint for the log analytics workspace
        workspace_private_link_scope = insights.PrivateLinkScope(
            f"{self._name}_log_analytics_workspace_private_link_scope",
            location="Global",
            resource_group_name=resource_group.name,
            scope_name=f"{self._name}-log-privatelinkscope",
        )
        workspace_private_endpoint = network.PrivateEndpoint(
            f"{self._name}_log_analytics_workspace_private_endpoint",
            location=props.location,
            private_endpoint_name=f"{self._name}-log-privatelinkscope-pep",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["AzureMonitor"],
                    name="LogAnalyticsWorkspacePrivateEndpoint",
                    private_link_service_id=workspace_private_link_scope.id,
                    request_message="Connection auto-approved.",
                )
            ],
            resource_group_name=resource_group.name,
            subnet=network.SubnetArgs(id=props.subnet_monitoring_id),
            opts=child_opts,
        )

        # Get workspace keys
        workspace_keys = operationalinsights.get_shared_keys(
            resource_group_name=resource_group.name,
            workspace_name=workspace.name,
        )

        # Add a private DNS record for each log analytics workspace custom DNS config
        workspace_private_endpoint.custom_dns_configs.apply(
            lambda cfgs: [
                self.private_record_set(cfg, props.dns_resource_group_name, child_opts)
                for cfg in cfgs
            ]
            if cfgs
            else []
        )

        # Link automation account to log analytics workspace
        automation_log_analytics_link = operationalinsights.LinkedService(
            f"{self._name}_automation_log_analytics_link",
            linked_service_name="Automation",
            resource_group_name=resource_group.name,
            resource_id=automation_account.id,
            workspace_name=workspace.name,
        )

        # Register outputs
        self.automation_account = automation_account
        self.automation_account_jrds_url = (
            automation_account.automation_hybrid_service_url
        )
        self.automation_account_agentsvc_url = (
            automation_account.automation_hybrid_service_url.apply(
                lambda url: url.replace("jrds", "agentsvc").replace(
                    "/automationAccounts/", "/accounts/"
                )
                if url
                else ""
            )
        )
        self.automation_account_modules = list(modules.keys())
        self.automation_account_primary_key = Output.secret(
            automation_keys.keys[0].value
        )
        self.log_analytics_workspace_id = workspace.customer_id
        self.log_analytics_workspace_key = (
            workspace_keys.primary_shared_key
            if workspace_keys.primary_shared_key
            else "UNKNOWN"
        )
        self.resource_group_name = resource_group.name

    def private_record_set(
        self,
        config: network.outputs.CustomDnsConfigPropertiesFormatResponse,
        resource_group_name: Input[str],
        child_opts: Optional[ResourceOptions] = None,
    ) -> network.PrivateRecordSet:
        """
        Create a PrivateRecordSet for a given CustomDnsConfigPropertiesFormatResponse

        Note that creating resources inside an .apply() is discouraged but not
        forbidden. This is the one way to create one resource for each entry in
        an Output[Sequence]. See https://github.com/pulumi/pulumi/issues/3849.
        """
        private_zone_name = [
            name for name in self.private_zone_names if name in config.fqdn
        ][0]
        record_name = config.fqdn.replace(f".{private_zone_name}", "")
        ip_address = config.ip_addresses[0] if config.ip_addresses else ""
        return network.PrivateRecordSet(
            f"{self._name}_private_a_record_{record_name}.{private_zone_name}",
            a_records=[network.ARecordArgs(ipv4_address=ip_address)],
            private_zone_name=f"privatelink.{private_zone_name}",
            record_type="A",
            relative_record_set_name=record_name,
            resource_group_name=resource_group_name,
            ttl=10,
            opts=child_opts,
        )
