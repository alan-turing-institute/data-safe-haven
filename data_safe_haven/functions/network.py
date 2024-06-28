import requests


def current_ip_address(*, as_cidr: bool = False) -> str:
    ip_address = requests.get("https://api.ipify.org", timeout=300).content.decode(
        "utf8"
    )
    if as_cidr:
        ip_address += "/32"
    return ip_address
