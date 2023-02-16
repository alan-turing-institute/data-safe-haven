# Standard library imports
import ipaddress
import math
from contextlib import suppress
from typing import List

# Local imports
from data_safe_haven.exceptions import DataSafeHavenIPRangeException


class AzureIPv4Range(ipaddress.IPv4Network):
    """Azure-aware IPv4 address range"""

    def __init__(
        self,
        ip_address_first: str | ipaddress.IPv4Address,
        ip_address_last: str | ipaddress.IPv4Address,
    ):
        networks = list(
            ipaddress.summarize_address_range(
                ipaddress.ip_address(ip_address_first),
                ipaddress.ip_address(ip_address_last),
            )
        )
        if len(networks) != 1:
            raise DataSafeHavenIPRangeException(
                f"{ip_address_first}-{ip_address_last} cannot be expressed as a single network range."
            )
        super().__init__(networks[0])
        self.subnets: List["AzureIPv4Range"] = []

    @classmethod
    def from_cidr(cls, ip_cidr: str) -> "AzureIPv4Range":
        network = ipaddress.IPv4Network(ip_cidr)
        return cls(network[0], network[-1])

    def available(self) -> List[ipaddress.IPv4Address]:
        """Azure reserves x.x.x.1 for the default gateway and (x.x.x.2, x.x.x.3) to map Azure DNS IPs."""
        return list(self.hosts())[3:]

    def next_subnet(self, number_of_addresses: int) -> "AzureIPv4Range":
        """Find the next unused subnet of a given size"""
        if not math.log2(number_of_addresses).is_integer():
            raise DataSafeHavenIPRangeException(
                f"Number of address '{number_of_addresses}' must be a power of 2"
            )
        ip_address_first = self[0]
        while True:
            ip_address_last = ip_address_first + int(number_of_addresses - 1)
            with suppress(DataSafeHavenIPRangeException):
                candidate = AzureIPv4Range(ip_address_first, ip_address_last)
                if not any(subnet.overlaps(candidate) for subnet in self.subnets):
                    self.subnets.append(candidate)
                    break
            ip_address_first = ip_address_first + number_of_addresses
        return candidate
