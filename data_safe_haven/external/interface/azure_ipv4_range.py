# Standard library imports
import ipaddress
from typing import List


class AzureIPv4Range(ipaddress.IPv4Network):
    """Azure-aware IPv4 address range"""

    def __init__(self, ip_address_first: str, ip_address_last: str):
        networks = list(
            ipaddress.summarize_address_range(
                ipaddress.ip_address(ip_address_first),
                ipaddress.ip_address(ip_address_last),
            )
        )
        if len(networks) != 1:
            raise ValueError(
                f"{ip_address_first}-{ip_address_last} cannot be expressed as a single network range."
            )
        super().__init__(networks[0])

    def available(self) -> List[ipaddress.IPv4Address]:
        """Azure reserves x.x.x.1 for the default gateway and (x.x.x.2, x.x.x.3) to map Azure DNS IPs."""
        return list(self.hosts())[3:]
