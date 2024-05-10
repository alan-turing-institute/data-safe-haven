from .enums import PermittedDomainCategories


def azure_dns_zone_names(resource_type: str | None = None) -> list[str]:
    """
    Return a list of DNS zones used by a given Azure resource type.
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


def permitted_domains(category: PermittedDomainCategories) -> list[str]:
    """
    Given a domain category, return a list of all domains to which access is permitted.
    """
    domains = {
        PermittedDomainCategories.APT_REPOSITORIES: [
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
        PermittedDomainCategories.AZURE_DNS_ZONES: azure_dns_zone_names(),
        PermittedDomainCategories.CLAMAV_UPDATES: [
            "clamav.net",
            "current.cvd.clamav.net",
            "database.clamav.net.cdn.cloudflare.net",
            "database.clamav.net",
        ],
        PermittedDomainCategories.MICROSOFT_GRAPH_API: [
            "graph.microsoft.com",
        ],
        PermittedDomainCategories.MICROSOFT_LOGIN: [
            "login.microsoftonline.com",
        ],
        PermittedDomainCategories.SOFTWARE_REPOSITORIES_R: [
            "cran.r-project.org",
        ],
        PermittedDomainCategories.SOFTWARE_REPOSITORIES_PYTHON: [
            "files.pythonhosted.org",
            "pypi.org",
        ],
        PermittedDomainCategories.TIME_SERVERS: [
            "time.google.com",
            "time1.google.com",
            "time2.google.com",
            "time3.google.com",
            "time4.google.com",
        ],
        PermittedDomainCategories.UBUNTU_KEYSERVER: [
            "keyserver.ubuntu.com",
        ],
    }
    # Add categories that are combinations of others
    domains[PermittedDomainCategories.SOFTWARE_REPOSITORIES] = (
        domains[PermittedDomainCategories.SOFTWARE_REPOSITORIES_R]
        + domains[PermittedDomainCategories.SOFTWARE_REPOSITORIES_PYTHON]
    )
    if category in domains:
        fqdns = domains[category]
    elif category == PermittedDomainCategories.ALL:
        fqdns = list(domains.values())  # type: ignore
    return sorted({domain for domains in fqdns for domain in domains})
