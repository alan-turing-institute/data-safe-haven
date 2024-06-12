import ipaddress
import math
from contextlib import suppress

from data_safe_haven.exceptions import DataSafeHavenIPRangeError


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
            msg = f"{ip_address_first}-{ip_address_last} cannot be expressed as a single network range."
            raise DataSafeHavenIPRangeError(msg)
        super().__init__(networks[0])
        self._subnets: list[AzureIPv4Range] = []

    @classmethod
    def from_cidr(cls, ip_cidr: str) -> "AzureIPv4Range":
        network = ipaddress.IPv4Network(ip_cidr)
        return cls(network[0], network[-1])

    @property
    def prefix(self) -> str:
        return str(self)

    def all_ips(self) -> list[ipaddress.IPv4Address]:
        """All IP addresses in the range"""
        return list(self.hosts())

    def available(self) -> list[ipaddress.IPv4Address]:
        """Azure reserves x.x.x.1 for the default gateway and (x.x.x.2, x.x.x.3) to map Azure DNS IPs."""
        return list(self.all_ips())[3:]

    def next_subnet(self, number_of_addresses: int) -> "AzureIPv4Range":
        """Find the next unused subnet of a given size"""
        if not math.log2(number_of_addresses).is_integer():
            msg = f"Number of address '{number_of_addresses}' must be a power of 2"
            raise DataSafeHavenIPRangeError(msg)
        ip_address_first = self[0]
        while True:
            ip_address_last = ip_address_first + int(number_of_addresses - 1)
            with suppress(DataSafeHavenIPRangeError):
                candidate = AzureIPv4Range(ip_address_first, ip_address_last)
                if not any(subnet.overlaps(candidate) for subnet in self._subnets):
                    self._subnets.append(candidate)
                    break
            ip_address_first = ip_address_first + number_of_addresses
        return candidate
