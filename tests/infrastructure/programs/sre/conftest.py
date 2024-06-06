from pulumi_azure_native import managedidentity, network, resources
from pytest import fixture

from data_safe_haven.infrastructure.common import SREIpRanges


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
