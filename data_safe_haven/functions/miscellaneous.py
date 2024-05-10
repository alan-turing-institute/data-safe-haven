import datetime

import pytz

from data_safe_haven.infrastructure.common import azure_dns_zone_names


def allowed_dns_lookups(category: str | None = None) -> list[str]:
    dns_lookups = {
        "apt_repositories": [
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
        "private_dns": azure_dns_zone_names(),
        "ubuntu_setup": ["keyserver.ubuntu.com"],
    }
    if category:
        fqdns = [dns_lookups[category]]
    else:
        fqdns = list(dns_lookups.values())
    return sorted({zone for zones in fqdns for zone in zones})


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
