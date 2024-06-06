from enum import UNIQUE, Enum, verify


@verify(UNIQUE)
class AzureDnsZoneNames(tuple[str, ...], Enum):
    """
    Return a list of DNS zones used by a given Azure resource type.
    See https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns for details.
    """

    AZURE_MONITOR = (
        "agentsvc.azure-automation.net",
        "blob.core.windows.net",
        "monitor.azure.com",
        "ods.opinsights.azure.com",
        "oms.opinsights.azure.com",
    )
    STORAGE_ACCOUNT = ("blob.core.windows.net", "file.core.windows.net")
    ALL = tuple(sorted(set(AZURE_MONITOR + STORAGE_ACCOUNT)))


@verify(UNIQUE)
class DatabaseSystem(str, Enum):
    MICROSOFT_SQL_SERVER = "mssql"
    POSTGRESQL = "postgresql"


@verify(UNIQUE)
class FirewallPriorities(int, Enum):
    """Priorities for firewall rules."""

    # All sources: 1000-1099
    ALL = 1000
    # SHM sources: 2000-2999
    SHM_IDENTITY_SERVERS = 2000
    # SRE sources: 3000-3999
    SRE_APT_PROXY_SERVER = 3000
    SRE_GUACAMOLE_CONTAINERS = 3100
    SRE_IDENTITY_CONTAINERS = 3200
    SRE_USER_SERVICES_SOFTWARE_REPOSITORIES = 3300
    SRE_WORKSPACES = 3400


@verify(UNIQUE)
class NetworkingPriorities(int, Enum):
    """Priorities for network security group rules."""

    # Azure services: 100 - 999
    AZURE_GATEWAY_MANAGER = 100
    AZURE_LOAD_BALANCER = 200
    AZURE_MONITORING_SOURCES = 300
    AZURE_PLATFORM_DNS = 400
    # SHM connections: 1000-1299
    INTERNAL_SELF = 1000
    INTERNAL_SHM_MONITORING_TOOLS = 1100
    # DNS connections: 1400-1499
    INTERNAL_SRE_DNS_SERVERS = 1400
    # SRE connections: 1500-2999
    INTERNAL_SRE_APPLICATION_GATEWAY = 1500
    INTERNAL_SRE_APT_PROXY_SERVER = 1600
    INTERNAL_SRE_DATA_CONFIGURATION = 1700
    INTERNAL_SRE_DATA_PRIVATE = 1800
    INTERNAL_SRE_GUACAMOLE_CONTAINERS = 1900
    INTERNAL_SRE_GUACAMOLE_CONTAINERS_SUPPORT = 2000
    INTERNAL_SRE_IDENTITY_CONTAINERS = 2100
    INTERNAL_SRE_MONITORING_TOOLS = 2200
    INTERNAL_SRE_USER_SERVICES_CONTAINERS = 2300
    INTERNAL_SRE_USER_SERVICES_CONTAINERS_SUPPORT = 2400
    INTERNAL_SRE_USER_SERVICES_DATABASES = 2500
    INTERNAL_SRE_USER_SERVICES_SOFTWARE_REPOSITORIES = 2600
    INTERNAL_SRE_WORKSPACES = 2700
    INTERNAL_SRE_ANY = 2999
    # Authorised external IPs: 3000-3499
    AUTHORISED_EXTERNAL_USER_IPS = 3100
    AUTHORISED_EXTERNAL_SSL_LABS_IPS = 3200
    # Wider internet: 3500-3999
    EXTERNAL_LINUX_UPDATES = 3600
    EXTERNAL_INTERNET = 3999
    # Deny all other: 4096
    ALL_OTHER = 4096


@verify(UNIQUE)
class PermittedDomains(tuple[str, ...], Enum):
    """Permitted domains for outbound connections."""

    APT_REPOSITORIES = (
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
    )
    AZURE_DNS_ZONES = AzureDnsZoneNames.ALL
    CLAMAV_UPDATES = (
        "clamav.net",
        "current.cvd.clamav.net",
        "database.clamav.net.cdn.cloudflare.net",
        "database.clamav.net",
    )
    MICROSOFT_GRAPH_API = ("graph.microsoft.com",)
    MICROSOFT_LOGIN = ("login.microsoftonline.com",)
    MICROSOFT_IDENTITY = MICROSOFT_GRAPH_API + MICROSOFT_LOGIN
    SOFTWARE_REPOSITORIES_PYTHON = (
        "files.pythonhosted.org",
        "pypi.org",
    )
    SOFTWARE_REPOSITORIES_R = ("cran.r-project.org",)
    SOFTWARE_REPOSITORIES = SOFTWARE_REPOSITORIES_PYTHON + SOFTWARE_REPOSITORIES_R
    UBUNTU_KEYSERVER = ("keyserver.ubuntu.com",)
    ALL = tuple(
        sorted(
            set(
                APT_REPOSITORIES
                + AZURE_DNS_ZONES
                + CLAMAV_UPDATES
                + MICROSOFT_GRAPH_API
                + MICROSOFT_LOGIN
                + SOFTWARE_REPOSITORIES_PYTHON
                + SOFTWARE_REPOSITORIES_R
                + UBUNTU_KEYSERVER
            )
        )
    )


@verify(UNIQUE)
class Ports(str, Enum):
    AZURE_MONITORING = "514"
    CLAMAV = "11371"
    DNS = "53"
    HTTP = "80"
    HTTPS = "443"
    LDAP_APRICOT = "1389"
    LINUX_UPDATE = "8000"
    MSSQL = "1433"
    NEXUS = "8081"
    NTP = "123"
    POSTGRESQL = "5432"
    RDP = "3389"
    SSH = "22"
    SQUID = "3128"


@verify(UNIQUE)
class SoftwarePackageCategory(str, Enum):
    ANY = "any"
    PRE_APPROVED = "pre-approved"
    NONE = "none"
