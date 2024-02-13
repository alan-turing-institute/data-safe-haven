"""Calculate SRE IP address ranges for a given SRE index"""

from data_safe_haven.external import AzureIPv4Range


class SREIpRanges:
    """Calculate SRE IP address ranges for a given SRE index"""

    max_index = 256

    def __init__(self, index: int) -> None:
        """Constructor"""
        self.vnet = AzureIPv4Range(f"10.{index}.0.0", f"10.{index}.255.255")
        self.application_gateway = self.vnet.next_subnet(256)
        self.data_configuration = self.vnet.next_subnet(8)
        self.data_private = self.vnet.next_subnet(8)
        self.guacamole_containers = self.vnet.next_subnet(8)
        self.guacamole_containers_support = self.vnet.next_subnet(8)
        self.identity_containers = self.vnet.next_subnet(8)
        self.identity_containers_support = self.vnet.next_subnet(8)
        self.user_services_containers = self.vnet.next_subnet(8)
        self.user_services_containers_support = self.vnet.next_subnet(8)
        self.user_services_databases = self.vnet.next_subnet(8)
        self.user_services_software_repositories = self.vnet.next_subnet(8)
        self.workspaces = self.vnet.next_subnet(256)


class SREDnsIpRanges:
    """Calculate SRE DNS IP address ranges."""

    def __init__(self) -> None:
        """Constructor"""
        self.vnet = AzureIPv4Range("192.168.0.0", "192.168.0.7")
