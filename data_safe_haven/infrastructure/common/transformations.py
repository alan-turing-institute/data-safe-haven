"""Common transformations needed when manipulating Pulumi resources"""

from pulumi import Output
from pulumi_azure_native import containerinstance, network, resources

from data_safe_haven.exceptions import DataSafeHavenPulumiError
from data_safe_haven.external import AzureIPv4Range


def get_address_prefixes_from_subnet(subnet: network.GetSubnetResult) -> list[str]:
    """Get list of CIDRs belonging to this subnet"""
    if address_prefixes := subnet.address_prefixes:
        return [str(p) for p in address_prefixes]
    if address_prefix := subnet.address_prefix:
        return [address_prefix]
    msg = f"Subnet '{subnet}' has no address prefix."
    raise DataSafeHavenPulumiError(msg)


def get_available_ips_from_subnet(subnet: network.GetSubnetResult) -> list[str]:
    """Get list of available IP addresses from a subnet"""
    if address_prefix := subnet.address_prefix:
        return [str(ip) for ip in AzureIPv4Range.from_cidr(address_prefix).available()]
    return []


def get_id_from_rg(rg: resources.ResourceGroup) -> Output[str]:
    """Get the ID of a resource group"""
    if isinstance(rg.id, Output):
        return rg.id
    msg = f"Resource group '{rg}' has no ID."
    raise DataSafeHavenPulumiError(msg)


def get_id_from_subnet(subnet: network.GetSubnetResult) -> str:
    """Get the ID of a subnet"""
    if id_ := subnet.id:
        return str(id_)
    msg = f"Subnet '{subnet}' has no ID."
    raise DataSafeHavenPulumiError(msg)


def get_id_from_vnet(vnet: network.VirtualNetwork) -> Output[str]:
    """Get the ID of a virtual network"""
    if isinstance(vnet.id, Output):
        return vnet.id
    msg = f"Virtual network '{vnet}' has no ID."
    raise DataSafeHavenPulumiError(msg)


def get_ip_address_from_container_group(
    container_group: containerinstance.ContainerGroup,
) -> Output[str]:
    """Get the IP address of a container group"""
    return container_group.ip_address.apply(
        lambda ip_address: (
            (ip_address.ip if ip_address.ip else "") if ip_address else ""
        )
    )


def get_ip_addresses_from_private_endpoint(
    endpoint: network.PrivateEndpoint,
) -> Output[list[str]]:
    """Get a list of IP addresses from a private endpoint"""
    if isinstance(endpoint.custom_dns_configs, Output):
        return endpoint.custom_dns_configs.apply(
            lambda cfgs: (
                list(
                    {
                        ip_address
                        for cfg in cfgs
                        for ip_address in (cfg.ip_addresses if cfg.ip_addresses else [])
                    }
                )
                if cfgs
                else []
            )
        )
    msg = f"Private endpoint '{endpoint}' has no IP addresses."
    raise DataSafeHavenPulumiError(msg)


def get_name_from_rg(rg: resources.ResourceGroup) -> Output[str]:
    """Get the name of a resource group"""
    if isinstance(rg.name, Output):
        return rg.name.apply(str)
    msg = f"Resource group '{rg}' has no name."
    raise DataSafeHavenPulumiError(msg)


def get_name_from_subnet(subnet: network.GetSubnetResult) -> str:
    """Get the name of a subnet"""
    if name := subnet.name:
        return str(name)
    msg = f"Subnet '{subnet}' has no name."
    raise DataSafeHavenPulumiError(msg)


def get_name_from_vnet(vnet: network.VirtualNetwork) -> Output[str]:
    """Get the name of a virtual network"""
    if isinstance(vnet.name, Output):
        return vnet.name.apply(str)
    msg = f"Virtual network '{vnet}' has no name."
    raise DataSafeHavenPulumiError(msg)


def get_subscription_id_from_rg(rg: resources.ResourceGroup) -> Output[str]:
    """Get the ID of a subscription from a resource group"""
    if isinstance(rg.id, Output):
        return rg.id.apply(lambda id_: id_.split("/resourceGroups/")[0])
    msg = f"Could not extract subscription ID from resource group '{rg}'."
    raise DataSafeHavenPulumiError(msg)
