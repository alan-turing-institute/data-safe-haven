import asyncio
from typing import Any
from unittest.mock import patch

import pulumi
import pulumi.runtime
from pulumi_azure_native import managedidentity, network, resources
from pytest import fixture

from data_safe_haven.config.config_sections import (
    ConfigSubsectionGiteaMirror,
)
from data_safe_haven.infrastructure.common import (
    DockerHubCredentials,
    SREIpRanges,
)
from data_safe_haven.infrastructure.programs.sre.dns_server import (
    SREDnsServerComponent,
    SREDnsServerProps,
)
from data_safe_haven.infrastructure.programs.sre.monitoring_elements import (
    SREMonitoringElementsComponent,
    SREMonitoringElementsProps,
)
from data_safe_haven.infrastructure.programs.sre.networking import (
    SRENetworkingComponent,
    SRENetworkingProps,
)
from data_safe_haven.infrastructure.programs.sre.remote_desktop import (
    SRERemoteDesktopComponent,
    SRERemoteDesktopProps,
)


class DataSafeHavenMocks(pulumi.runtime.Mocks):
    """Configuration for Pulumi mocks"""

    def __init__(self) -> None:
        # Avoid "DeprecationWarning: There is no current event loop"
        # See https://stackoverflow.com/a/73884759
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

    def new_resource(
        self, args: pulumi.runtime.MockResourceArgs
    ) -> tuple[str | None, dict[Any, Any]]:
        state = dict(args.inputs)

        if args.typ == "azure-native:dns:Zone":
            # Ensure a value is available for the nameservers
            # Otherwise these come through as None and the tests fail
            state["nameServers"] = [
                "ns1.example.com",
            ]
        elif args.typ == "azure-native:network:VirtualNetwork":
            # Ensure a value is set for the VirtualNetwork name
            # Otherwise this comes through as None and the tests fail
            state["name"] = state["virtualNetworkName"]

        resources = (args.name + "_id", state)
        return resources

    def call(
        self, args: pulumi.runtime.MockCallArgs
    ) -> tuple[dict[Any, Any], list[tuple[str, str]] | None]:
        if args.token == "azure-native:network:getSubnet":  # noqa: S105
            # Ensure we return a validly formed subnet
            # Otherwise this comes through as None and the tests fail
            return (
                {
                    "id": "/subscriptions/test/subnets/subnet1",
                    "name": "subnet1",
                    "addressPrefix": "10.0.0.0/24",
                },
                [],
            )
        return ({}, [])


pulumi.runtime.set_mocks(
    DataSafeHavenMocks(),
    preview=False,
)


## Avoids a delayed return value causing the tests to fail
@fixture(autouse=True)
def patch_ips() -> pulumi.Output[list[str]]:
    with patch(
        "data_safe_haven.infrastructure.components.composite.postgresql_database.get_ip_addresses_from_private_endpoint"
    ) as mock:
        mock.return_value = pulumi.Output.from_input(["10.0.0.0"])
        yield mock


#
# Constants
#
@fixture
def location() -> str:
    return "uksouth"


@fixture
def resource_group_name() -> str:
    return "rg-example"


@fixture
def resource_group(location: str, resource_group_name: str) -> resources.ResourceGroup:
    return resources.ResourceGroup(
        "resource_group",
        location=location,
        resource_group_name=resource_group_name,
    )


@fixture
def sre_fqdn() -> str:
    return "sre.example.com"


@fixture
def sre_index() -> int:
    return 1


@fixture
def stack_name() -> str:
    return "stack-example"


@fixture
def tags() -> dict[str, str]:
    return {"key": "value"}


@fixture
def shm_fqdn() -> str:
    return "shm.example.com"


@fixture
def ldap_root_dn(shm_fqdn: str) -> str:
    return f"DC={shm_fqdn.replace('.', ',DC=')}"


@fixture
def ldap_group_search_base(ldap_root_dn: str) -> str:
    return f"OU=groups,{ldap_root_dn}"


@fixture
def ldap_username_attribute() -> str:
    return "uid"


@fixture
def ldap_user_search_base(ldap_root_dn: str) -> str:
    return f"OU=users,{ldap_root_dn}"


@fixture
def ldap_server_hostname() -> str:
    return "ldap_server.example.com}"


@fixture
def timezone() -> str:
    return "UTC"


#
# Pulumi resources
#
@fixture
def identity_key_vault_reader(
    location: str, resource_group_name: str, stack_name: str
) -> managedidentity.UserAssignedIdentity:
    return managedidentity.UserAssignedIdentity(
        "identity_key_vault_reader",
        location=location,
        resource_group_name=resource_group_name,
        resource_name_=f"{stack_name}-id-key-vault-reader",
    )


@fixture
def subnet_application_gateway() -> network.GetSubnetResult:
    return network.GetSubnetResult(
        address_prefix=SREIpRanges.application_gateway.prefix,
        id="subnet_application_gateway_id",
    )


@fixture
def subnet_guacamole_containers() -> network.GetSubnetResult:
    return network.GetSubnetResult(
        address_prefix=SREIpRanges.guacamole_containers.prefix,
        id="subnet_guacamole_containers_id",
    )


@fixture
def subnet_apt_proxy_server() -> network.GetSubnetResult:
    return network.GetSubnetResult(
        address_prefix=SREIpRanges.apt_proxy_server.prefix,
        id="subnet_apt_proxy_server_id",
    )


@fixture
def subnet_clamav_mirror() -> network.GetSubnetResult:
    return network.GetSubnetResult(
        address_prefix=SREIpRanges.clamav_mirror.prefix,
        id="subnet_clamav_mirror_id",
    )


@fixture
def subnet_firewall() -> network.GetSubnetResult:
    return network.GetSubnetResult(
        address_prefix=SREIpRanges.firewall.prefix,
        id="subnet_firewall_id",
    )


@fixture
def subnet_firewall_management() -> network.GetSubnetResult:
    return network.GetSubnetResult(
        address_prefix=SREIpRanges.firewall_management.prefix,
        id="subnet_firewall_management_id",
    )


@fixture
def subnet_identity_containers() -> network.GetSubnetResult:
    return network.GetSubnetResult(
        address_prefix=SREIpRanges.identity_containers.prefix,
        id="subnet_identity_containers_id",
    )


@fixture
def subnet_user_services_software_repositories() -> network.GetSubnetResult:
    return network.GetSubnetResult(
        address_prefix=SREIpRanges.user_services_software_repositories.prefix,
        id="subnet_user_services_software_repositories_id",
    )


@fixture
def subnet_user_services_gitea_mirror() -> network.GetSubnetResult:
    return network.GetSubnetResult(
        address_prefix=SREIpRanges.user_services_gitea_mirror.prefix,
        id="subnet_user_services_gitea_mirror_id",
    )


@fixture
def subnet_user_services_containers() -> network.GetSubnetResult:
    return network.GetSubnetResult(
        address_prefix=SREIpRanges.user_services_containers.prefix,
        id="subnet_user_services_containers_id",
    )


@fixture
def subnet_workspaces() -> network.GetSubnetResult:
    return network.GetSubnetResult(
        address_prefix=SREIpRanges.workspaces.prefix,
        id="subnet_workspaces_id",
    )


@fixture
def subnet_monitoring() -> network.GetSubnetResult:
    return network.GetSubnetResult(
        address_prefix=SREIpRanges.monitoring.prefix,
        id="subnet_monitoring_id",
    )


@fixture
def subnet_dns_sidecar() -> network.GetSubnetResult:
    return network.GetSubnetResult(
        address_prefix=SREIpRanges.dns_sidecar.prefix,
        id="subnet_dns_sidecar_id",
    )


@fixture
def dockerhub_credentials() -> DockerHubCredentials:
    return DockerHubCredentials(
        access_token="docker_token",
        server="docker_server",
        username="docker_username",
    )


@fixture
def admin_group_name() -> str:
    return "Data Safe Haven SRE unit test Administrators"


@fixture
def user_group_name() -> str:
    return "Data Safe Haven SRE unit test Users"


@fixture
def ldap_user_filter(
    admin_group_name: str, ldap_group_search_base: str, user_group_name: str
) -> str:
    return "".join(
        [
            "(&",
            "(objectClass=posixAccount)",
            "(|",
            *(
                f"(memberOf=CN={group_name},{ldap_group_search_base})"
                for group_name in (admin_group_name, user_group_name)
            ),
            ")",
            ")",
        ]
    )


@fixture
def ldap_group_filter(
    admin_group_name: str, ldap_group_search_base: str, user_group_name: str
) -> str:
    return "".join(
        [
            "(&",
            "(objectClass=posixGroup)",
            "(|",
            *(
                f"(CN={group_name})"
                for group_name in (admin_group_name, user_group_name)
            ),
            *(
                f"(memberOf=CN=Primary user groups for {group_name},{ldap_group_search_base})"
                for group_name in (admin_group_name, user_group_name)
            ),
            ")",
            ")",
        ]
    )


@fixture
def monitoring_elements(
    stack_name: str,
    location: str,
    resource_group: resources.ResourceGroup,
    tags: dict[str, str],
    timezone: str,
) -> SREMonitoringElementsComponent:
    return SREMonitoringElementsComponent(
        "sre_monitoring_elements",
        stack_name,
        SREMonitoringElementsProps(
            location=location,
            resource_group_name=resource_group.name,
            timezone=timezone,
        ),
        tags=tags,
    )


@fixture
def dns(
    stack_name: str,
    monitoring_elements: SREMonitoringElementsComponent,
    dockerhub_credentials: DockerHubCredentials,
    location: str,
    resource_group: resources.ResourceGroup,
    shm_fqdn: str,
    tags: dict[str, str],
    timezone: str,
) -> SREDnsServerComponent:
    return SREDnsServerComponent(
        "sre_dns_server",
        stack_name,
        SREDnsServerProps(
            allow_workspace_internet=False,
            data_collection_endpoint_id=monitoring_elements.data_collection_endpoint.id,
            data_collection_rule_id=monitoring_elements.data_collection_rule_vms.id,
            dockerhub_credentials=dockerhub_credentials,
            location=location,
            resource_group_name=resource_group.name,
            maintenance_configuration_id=monitoring_elements.maintenance_configuration.id,
            shm_fqdn=shm_fqdn,
            timezone=timezone,
        ),
        tags=tags,
    )


@fixture
def networking(
    stack_name: str,
    dns: SREDnsServerComponent,
    location: str,
    resource_group: resources.ResourceGroup,
    shm_fqdn: str,
    tags: dict[str, str],
) -> SRENetworkingComponent:
    return SRENetworkingComponent(
        "sre_networking",
        stack_name,
        SRENetworkingProps(
            dns_private_zones=dns.private_zones,
            dns_server_ip=dns.ip_address,
            dns_virtual_network=dns.virtual_network,
            location=location,
            resource_group_name=resource_group.name,
            shm_fqdn=shm_fqdn,
            shm_location=location,
            shm_resource_group_name=resource_group.name,
            shm_subscription_id="abcd-0123-abcd-0123",
            shm_zone_name=shm_fqdn,
            sre_name="sre-name",
            use_gitea_mirror=True,
            use_software_repositories=True,
            user_public_ip_ranges=["10.0.0.0/24"],
        ),
        tags=tags,
    )


@fixture
def repository_data() -> ConfigSubsectionGiteaMirror:
    return ConfigSubsectionGiteaMirror(
        repositories=[],
    )


@fixture
def remote_desktop_props(
    admin_group_name: str,
    dns: SREDnsServerComponent,
    dockerhub_credentials: DockerHubCredentials,
    ldap_group_filter: str,
    ldap_group_search_base: str,
    ldap_server_hostname: str,
    ldap_user_filter: str,
    ldap_user_search_base: str,
    location: str,
    monitoring_elements: SREMonitoringElementsComponent,
    networking: SRENetworkingComponent,
    resource_group: resources.ResourceGroup,
    user_group_name: str,
) -> SRERemoteDesktopProps:
    return SRERemoteDesktopProps(
        admin_group_name=admin_group_name,
        allow_copy=True,
        allow_paste=True,
        database_password="database_password",
        dns_server_ip=dns.ip_address,
        dockerhub_credentials=dockerhub_credentials,
        entra_application_id="entra_application_id",
        entra_application_url="https://entra-application.example.com",
        entra_tenant_id="entra_tenant_id",
        ldap_group_filter=ldap_group_filter,
        ldap_group_search_base=ldap_group_search_base,
        ldap_server_hostname=ldap_server_hostname,
        ldap_server_port=9999,
        ldap_user_filter=ldap_user_filter,
        ldap_user_search_base=ldap_user_search_base,
        location=location,
        log_analytics_workspace=monitoring_elements.workspace_analytics,
        resource_group_name=resource_group.name,
        storage_account_key="storage_key",
        storage_account_name="storage_account",
        subnet_guacamole_containers=networking.subnet_guacamole_containers,
        subnet_guacamole_containers_support=networking.subnet_guacamole_containers_support,
        user_group_name=user_group_name,
    )


@fixture
def remote_desktop_component(
    remote_desktop_props: SRERemoteDesktopProps,
    stack_name: str,
    tags: dict[str, str],
) -> SRERemoteDesktopComponent:
    return SRERemoteDesktopComponent(
        name="remote-desktop-name",
        stack_name=stack_name,
        props=remote_desktop_props,
        tags=tags,
    )
