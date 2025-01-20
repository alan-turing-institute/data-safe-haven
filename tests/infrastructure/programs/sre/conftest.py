import pulumi
import pulumi.runtime
from pulumi_azure_native import managedidentity, network, resources
from pytest import fixture

from data_safe_haven.infrastructure.common import SREIpRanges


class DataSafeHavenMocks(pulumi.runtime.Mocks):
    """Configuration for Pulumi mocks"""

    def new_resource(self, args: pulumi.runtime.MockResourceArgs):
        resources = [args.name + "_id", args.inputs]
        return resources

    def call(self, _: pulumi.runtime.MockCallArgs):
        return {}


pulumi.runtime.set_mocks(
    DataSafeHavenMocks(),
    preview=False,
)


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
def resource_group(location, resource_group_name) -> resources.ResourceGroup:
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


#
# Pulumi resources
#
@fixture
def identity_key_vault_reader(
    location, resource_group_name, stack_name
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
