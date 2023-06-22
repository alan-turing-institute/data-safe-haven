"""Common transformations needed when manipulating Pulumi resources"""
# Standard library imports
from typing import List

# Third party imports
from pulumi import Input, Output
from pulumi_azure_native import network, resources

# Local imports
from data_safe_haven.exceptions import DataSafeHavenPulumiException
from data_safe_haven.external.interface import AzureIPv4Range


def get_available_ips_from_subnet(subnet: network.GetSubnetResult) -> List[str]:
    """Get list of available IP addresses from a subnet"""
    if address_prefix := subnet.address_prefix:
        return [str(ip) for ip in AzureIPv4Range.from_cidr(address_prefix).available()]
    return []


def get_id_from_rg(rg: resources.ResourceGroup) -> Input[str]:
    """Get the ID of a resource group"""
    if isinstance(rg.id, Output):
        return rg.id
    raise DataSafeHavenPulumiException(f"Resource group '{rg.name}' has no ID.")


def get_id_from_subnet(subnet: network.GetSubnetResult) -> str:
    """Get the ID of a subnet"""
    if id_ := subnet.id:
        return str(id_)
    raise DataSafeHavenPulumiException(f"Subnet '{subnet.name}' has no ID.")


def get_ip_addresses_from_private_endpoint(
    endpoint: network.PrivateEndpoint,
) -> Input[List[str]]:
    """Get a list of IP addresses from a private endpoint"""
    if isinstance(endpoint.custom_dns_configs, Output):
        return endpoint.custom_dns_configs.apply(
            lambda cfgs: sum(
                [list(cfg.ip_addresses) if cfg.ip_addresses else [] for cfg in cfgs], []
            )
            if cfgs
            else []
        )
    raise DataSafeHavenPulumiException(
        f"Private endpoint '{endpoint.name}' has no IP addresses."
    )


def get_name_from_rg(rg: resources.ResourceGroup) -> Input[str]:
    """Get the name of a resource group"""
    if isinstance(rg.name, Output):
        return rg.name.apply(lambda s: str(s))
    raise DataSafeHavenPulumiException(f"Resource group '{rg.id}' has no name.")


def get_name_from_subnet(subnet: network.GetSubnetResult) -> str:
    """Get the name of a subnet"""
    if name := subnet.name:
        return str(name)
    raise DataSafeHavenPulumiException(f"Subnet '{subnet.id}' has no name.")


def get_name_from_vnet(vnet: network.VirtualNetwork) -> Input[str]:
    """Get the ID of a virtual network"""
    if isinstance(vnet.name, Output):
        return vnet.name.apply(lambda s: str(s))
    raise DataSafeHavenPulumiException(f"Virtual network '{vnet.id}' has no name.")
