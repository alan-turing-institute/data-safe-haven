import requests

from data_safe_haven.exceptions import DataSafeHavenValueError


def current_ip_address(*, as_cidr: bool = False) -> str:
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
