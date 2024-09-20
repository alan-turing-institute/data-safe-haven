"""Calculate SRE IP address ranges for a given SRE index"""

from dataclasses import dataclass

from data_safe_haven.external import AzureIPv4Range


@dataclass(frozen=True)
class SREIpRanges:
    """Calculate SRE IP address ranges for a given SRE index"""

    vnet = AzureIPv4Range("10.0.0.0", "10.0.255.255")
    application_gateway = vnet.next_subnet(256)
    apt_proxy_server = vnet.next_subnet(8)
    clamav_mirror = vnet.next_subnet(8)
    data_configuration = vnet.next_subnet(8)
    data_private = vnet.next_subnet(8)
    desired_state = vnet.next_subnet(8)
    firewall = vnet.next_subnet(64)  # 64 address minimum
    firewall_management = vnet.next_subnet(64)  # 64 address minimum
    guacamole_containers = vnet.next_subnet(8)
    guacamole_containers_support = vnet.next_subnet(8)
    identity_containers = vnet.next_subnet(8)
    monitoring = vnet.next_subnet(32)
    user_services_containers = vnet.next_subnet(8)
    user_services_containers_support = vnet.next_subnet(8)
    user_services_databases = vnet.next_subnet(8)
    user_services_software_repositories = vnet.next_subnet(8)
    workspaces = vnet.next_subnet(256)


@dataclass(frozen=True)
class SREDnsIpRanges:
    """Calculate SRE DNS IP address ranges."""

    vnet = AzureIPv4Range("192.168.0.0", "192.168.0.7")
