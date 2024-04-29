import datetime

import pytz


def allowed_dns_lookups(category: str | None = None) -> list[str]:
    dns_lookups = {
        "apt_updates": [
            # "apt.postgresql.org",
            "archive.ubuntu.com",
            "azure.archive.ubuntu.com",
            "changelogs.ubuntu.com",
            "cloudapp.azure.com",  # this is where azure.archive.ubuntu.com is hosted
            "deb.debian.org",
            # "d20rj4el6vkp4c.cloudfront.net",
            # "dbeaver.io",
            # "packages.gitlab.com",
            "packages.microsoft.com",
            # "qgis.org",
            "security.ubuntu.com",
            # "ubuntu.qgis.org"
        ],
        "clamav": ["clamav.net", "database.clamav.net.cdn.cloudflare.net"],
        "oauth": ["login.microsoftonline.com"],
        "package_repositories": [
            "cran.r-project.org",
            "files.pythonhosted.org",
            "pypi.org",
        ],
        "private_dns": ordered_private_dns_zones(),
        "ubuntu_setup": ["keyserver.ubuntu.com"],
    }
    if category:
        fqdns = [dns_lookups[category]]
    else:
        fqdns = list(dns_lookups.values())
    return sorted({zone for zones in fqdns for zone in zones})


def ordered_private_dns_zones(resource_type: str | None = None) -> list[str]:
    """
    Return required DNS zones for a given resource type.
    See https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns for details.
    """
    dns_zones = {
        "Azure Automation": ["azure-automation.net"],
        "Azure Monitor": [
            "agentsvc.azure-automation.net",
            "blob.core.windows.net",
            "monitor.azure.com",
            "ods.opinsights.azure.com",
            "oms.opinsights.azure.com",
        ],
        "Storage account": ["blob.core.windows.net", "file.core.windows.net"],
    }
    if resource_type and (resource_type in dns_zones):
        return dns_zones[resource_type]
    return sorted({zone for zones in dns_zones.values() for zone in zones})


def time_as_string(hour: int, minute: int, timezone: str) -> str:
    """Get the next occurence of a repeating daily time as a string"""
    dt = datetime.datetime.now(datetime.UTC).replace(
        hour=hour,
        minute=minute,
        second=0,
        microsecond=0,
        tzinfo=pytz.timezone(timezone),
    ) + datetime.timedelta(days=1)
    return dt.isoformat()
