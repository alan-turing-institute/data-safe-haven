# Standard library imports
import base64
import datetime
import hashlib
import pytz
import secrets
import string
from typing import List, Optional, Sequence


def alphanumeric(input_string: str) -> str:
    """Strip any characters that are not letters or numbers from a string."""
    return "".join(
        filter(lambda x: x in (string.ascii_letters + string.digits), input_string)
    )


def b64encode(input_string: str) -> str:
    return base64.b64encode(input_string.encode("utf-8")).decode()


def hex_string(length: int) -> str:
    """Generate a string of 'length' random hexadecimal characters."""
    return secrets.token_hex(length)


def ordered_private_dns_zones(resource_type: Optional[str] = None) -> List[str]:
    """
    Return required DNS zones for a given resource type.
    See https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns for details.
    """
    dns_zones = {
        "Azure Automation": ["azure-automation.net"],
        "Azure Monitor": [
            "agentsvc.azure-automation.net",
            # "applicationinsights.azure.com", # not currently used
            "blob.core.windows.net",
            "monitor.azure.com",
            "ods.opinsights.azure.com",
            "oms.opinsights.azure.com",
        ],
        "Storage account": ["blob.core.windows.net"],
    }
    if resource_type and (resource_type in dns_zones):
        return dns_zones[resource_type]
    return sorted(set(zone for zones in dns_zones.values() for zone in zones))


def password(length: int) -> str:
    """Generate a string of 'length' random alphanumeric characters. Require at least one lower-case, one upper-case and one digit."""
    alphabet = string.ascii_letters + string.digits
    while True:
        password_ = "".join(secrets.choice(alphabet) for _ in range(length))
        if (
            any(c.islower() for c in password_)
            and any(c.isupper() for c in password_)
            and any(c.isdigit() for c in password_)
        ):
            break
    return password_


def random_letters(length: int) -> str:
    """Generate a string of 'length' random letters."""
    return "".join(secrets.choice(string.ascii_letters) for _ in range(length))


def replace_separators(input_string: str, separator: str = "") -> str:
    """Return a string using underscores as a separator"""
    return (
        input_string.replace(" ", separator)
        .replace("_", separator)
        .replace("-", separator)
        .replace(".", separator)
    )


def sha256hash(input_string: str) -> str:
    """Return the SHA256 hash of a string as a string."""
    return hashlib.sha256(str.encode(input_string, encoding="utf-8")).hexdigest()


def time_as_string(hour: int, minute: int, timezone: str) -> str:
    """Get the next occurence of a repeating daily time as a string"""
    dt = datetime.datetime.now().replace(
        hour=hour,
        minute=minute,
        second=0,
        microsecond=0,
        tzinfo=pytz.timezone(timezone),
    ) + datetime.timedelta(days=1)
    return dt.isoformat()


def truncate_tokens(tokens: Sequence[str], max_length: int) -> List[str]:
    output_tokens = list(tokens)
    token_lengths = [len(t) for t in output_tokens]
    while sum(token_lengths) > max_length:
        for idx in range(len(output_tokens)):
            if len(output_tokens[idx]) == max(token_lengths):
                output_tokens[idx] = output_tokens[idx][:-1]
                token_lengths[idx] -= 1
                break
    return output_tokens
