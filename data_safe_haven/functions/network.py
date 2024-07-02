import ipaddress
from collections.abc import Sequence

import requests

from data_safe_haven.exceptions import DataSafeHavenValueError


def current_ip_address(*, as_cidr: bool = False) -> str:
    """
    Get the IP address of the current device.

    Returns:
        str: the IP address

    Raises:
        DataSafeHavenValueError: if the current IP address could not be determined
    """
    try:
        ip_address = requests.get("https://api.ipify.org", timeout=300).content.decode(
            "utf8"
        )
        if as_cidr:
            ip_address += "/32"
        return ip_address
    except requests.RequestException as exc:
        msg = "Could not determine IP address."
        raise DataSafeHavenValueError(msg) from exc


def ip_address_in_list(ip_address_list: Sequence[str]) -> bool:
    """
    Check whether current IP address belongs to a list of authorised addresses

    Returns:
        bool: True if in list, False if not

    Raises:
        DataSafeHavenValueError: if the current IP address could not be determined
    """
    ip_address = current_ip_address()
    if ip_address not in [str(ipaddress.IPv4Address(ip)) for ip in ip_address_list]:
        return False
    return True
