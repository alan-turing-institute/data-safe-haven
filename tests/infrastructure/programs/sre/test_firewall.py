import pulumi
import pulumi.runtime
from pulumi_azure_native import network
from pytest import fixture

from data_safe_haven.functions import replace_separators
from data_safe_haven.infrastructure.programs.sre.firewall import (
    SREFirewallComponent,
    SREFirewallProps,
)
from data_safe_haven.infrastructure.programs.sre.monitoring import (
    SREMonitoringComponent,
    SREMonitoringProps,
)
from data_safe_haven.types import AzureDnsZoneNames


@fixture
def sre_monitoring_component(
    location: str,
    resource_group_name: str,
    stack_name: str,
    subnet_monitoring: network.GetSubnetResult,
    tags: dict[str, str],
) -> SREMonitoringComponent:
    return SREMonitoringComponent(
        "test_sre_monitoring",
        stack_name,
        SREMonitoringProps(
            dns_private_zones={
                dns_zone_name: network.PrivateZone(
                    replace_separators(
                        f"test_sre_dns_server_private_zone_{dns_zone_name}", "_"
                    ),
                    location="Global",
                    private_zone_name=f"privatelink.{dns_zone_name}",
                    resource_group_name=resource_group_name,
                    tags=tags,
                )
                for dns_zone_name in AzureDnsZoneNames.ALL
            },  # TODO: Check if this works
            location=location,
            resource_group_name=resource_group_name,
            subnet=subnet_monitoring,
            timezone="Europe/London",
        ),
        tags=tags,
    )


@fixture
def firewall_props_internet_enabled(
    location: str,
    resource_group_name: str,
    stack_name: str,
    sre_monitoring_component: SREMonitoringComponent,
    subnet_apt_proxy_server: network.GetSubnetResult,
    subnet_clamav_mirror: network.GetSubnetResult,
    subnet_firewall: network.GetSubnetResult,
    subnet_firewall_management: network.GetSubnetResult,
    subnet_guacamole_containers: network.GetSubnetResult,
    subnet_identity_containers: network.GetSubnetResult,
    subnet_user_services_software_repositories: network.GetSubnetResult,
    subnet_workspaces: network.GetSubnetResult,
) -> SREFirewallProps:
    return SREFirewallProps(
        allow_workspace_internet=True,
        location=location,
        log_analytics_workspace=sre_monitoring_component,
        resource_group_name=resource_group_name,
        route_table_name=f"{stack_name}-route-table",
        subnet_apt_proxy_server=subnet_apt_proxy_server,
        subnet_clamav_mirror=subnet_clamav_mirror,
        subnet_firewall=subnet_firewall,
        subnet_firewall_management=subnet_firewall_management,
        subnet_guacamole_containers=subnet_guacamole_containers,
        subnet_identity_containers=subnet_identity_containers,
        subnet_user_services_software_repositories=subnet_user_services_software_repositories,
        subnet_workspaces=subnet_workspaces,
    )


@fixture
def firewall_props_internet_disabled(
    location: str,
    resource_group_name: str,
    stack_name: str,
    sre_monitoring_component: SREMonitoringComponent,
    subnet_apt_proxy_server: network.GetSubnetResult,
    subnet_clamav_mirror: network.GetSubnetResult,
    subnet_firewall: network.GetSubnetResult,
    subnet_firewall_management: network.GetSubnetResult,
    subnet_guacamole_containers: network.GetSubnetResult,
    subnet_identity_containers: network.GetSubnetResult,
    subnet_user_services_software_repositories: network.GetSubnetResult,
    subnet_workspaces: network.GetSubnetResult,
) -> SREFirewallProps:
    return SREFirewallProps(
        allow_workspace_internet=False,
        location=location,
        log_analytics_workspace=sre_monitoring_component,
        resource_group_name=resource_group_name,
        route_table_name=f"{stack_name}-route-table",
        subnet_apt_proxy_server=subnet_apt_proxy_server,
        subnet_clamav_mirror=subnet_clamav_mirror,
        subnet_firewall=subnet_firewall,
        subnet_firewall_management=subnet_firewall_management,
        subnet_guacamole_containers=subnet_guacamole_containers,
        subnet_identity_containers=subnet_identity_containers,
        subnet_user_services_software_repositories=subnet_user_services_software_repositories,
        subnet_workspaces=subnet_workspaces,
    )


class TestSREFirewallComponent:

    @pulumi.runtime.test
    def test_component_allow_workspace_internet_enabled(
        self,
        firewall_props_internet_enabled: SREFirewallProps,
        stack_name: str,
        tags: dict[str, str],
    ):

        firewall_component: SREFirewallComponent = SREFirewallComponent(
            name="sre_firewall_with_internet",
            stack_name=stack_name,
            props=firewall_props_internet_enabled,
            tags=tags,
        )

        def assert_on_firewall_rules(
            args: list,
        ):
            application_rule_collections = args[0]
            network_rule_collections = args[1]

            # TODO: Be more precise in rule filtering.
            allow_internet_collection: list[dict] = [
                rule_collection
                for rule_collection in network_rule_collections
                if rule_collection["name"] == "workspaces-allow-all"
            ]

            assert len(application_rule_collections) == 5
            assert len(allow_internet_collection) == 1

        pulumi.Output.all(
            firewall_component.firewall.application_rule_collections,
            firewall_component.firewall.network_rule_collections,
        ).apply(assert_on_firewall_rules)

    @pulumi.runtime.test
    def test_component_allow_workspace_internet_disabled(
        self,
        firewall_props_internet_disabled: SREFirewallProps,
        stack_name: str,
        tags: dict[str, str],
    ):
        firewall_component: SREFirewallComponent = SREFirewallComponent(
            name="sre_firewall_with_internet",
            stack_name=stack_name,
            props=firewall_props_internet_disabled,
            tags=tags,
        )

        def assert_on_firewall_rules(
            args: list,
        ):
            application_rule_collections = args[0]
            network_rule_collections = args[1]

            assert len(application_rule_collections) > 0
            assert network_rule_collections is None

        pulumi.Output.all(
            firewall_component.firewall.application_rule_collections,
            firewall_component.firewall.network_rule_collections,
        ).apply(assert_on_firewall_rules)
