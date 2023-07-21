# Standard library imports
import datetime
from typing import Any, Dict, List, Optional

# Third-party imports
import pytz


def as_dict(object: Any) -> Dict[str, Any]:
    if (
        not isinstance(object, dict)
        and hasattr(object, "keys")
        and all(isinstance(x, str) for x in object.keys())
    ):
        raise TypeError(f"{object} {type(object)} is not a valid Dict[str, Any]")
    return object


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
        "Storage account": ["blob.core.windows.net", "file.core.windows.net"],
    }
    if resource_type and (resource_type in dns_zones):
        return dns_zones[resource_type]
    return sorted(set(zone for zones in dns_zones.values() for zone in zones))


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
