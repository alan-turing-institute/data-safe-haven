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
class AzureSdkCredentialScope(str, Enum):
    DEFAULT = "https://management.azure.com/.default"
    GRAPH_API = "https://graph.microsoft.com/.default"
    KEY_VAULT = "https://vault.azure.net"


@verify(UNIQUE)
class AzureServiceTag(str, Enum):
    INTERNET = "Internet"


@verify(UNIQUE)
class DatabaseSystem(str, Enum):
    MICROSOFT_SQL_SERVER = "mssql"
    POSTGRESQL = "postgresql"


@verify(UNIQUE)
class EntraApplicationId(str, Enum):
    MICROSOFT_GRAPH = "00000003-0000-0000-c000-000000000000"


@verify(UNIQUE)
class EntraAppPermissionType(str, Enum):
    APPLICATION = "Role"
    DELEGATED = "Scope"


@verify(UNIQUE)
class EntraSignInAudienceType(str, Enum):
    ANY_TENANT = "AzureADMultipleOrgs"
    ANY_TENANT_OR_PERSONAL = "AzureADandPersonalMicrosoftAccount"
    PERSONAL = "PersonalMicrosoftAccount"
    THIS_TENANT = "AzureADMyOrg"


@verify(UNIQUE)
class FirewallPriorities(int, Enum):
    """Priorities for firewall rules."""

    # All sources: 1000-1099
    ALL = 1000
    # SHM sources: 2000-2999
    SHM_IDENTITY_SERVERS = 2000
    # SRE sources: 3000-3999
    SRE_APT_PROXY_SERVER = 3000
    SRE_CLAMAV_MIRROR = 3100
    SRE_GUACAMOLE_CONTAINERS = 3200
    SRE_IDENTITY_CONTAINERS = 3300
    SRE_USER_SERVICES_SOFTWARE_REPOSITORIES = 3400
    SRE_WORKSPACES = 3500
    SRE_WORKSPACES_DENY = 3550


@verify(UNIQUE)
class ForbiddenDomains(tuple[str, ...], Enum):
    # Block snap upload to the Snap store at snapcraft.io
    # Upload is through dashboard.snapscraft.io and requires a client to be logged in to
    # an Ubuntu account.
    # Login is through login.ubuntu.com.
    # However, once successfully authorised, it is not necessary to reach
    # login.ubuntu.com before uploading.
    # Therefore we should block access to both domains.
    UBUNTU_SNAPCRAFT = (
        "dashboard.snapcraft.io",  # upload endpoint
        "login.ubuntu.com",  # login endpoint (provides auth for upload)
        "upload.apps.ubuntu.com",
    )


@verify(UNIQUE)
class NetworkingPriorities(int, Enum):
    """Priorities for network security group rules."""

    # Azure services: 100 - 999
    AZURE_GATEWAY_MANAGER = 100
    AZURE_LOAD_BALANCER = 200
    AZURE_MONITORING_SOURCES = 300
    AZURE_PLATFORM_DNS = 400
    # DNS connections: 1000-1499
    INTERNAL_SRE_DNS_SERVERS = 1000
    # SRE connections: 1500-2999
    INTERNAL_SRE_SELF = 1500
    INTERNAL_SRE_APPLICATION_GATEWAY = 1600
    INTERNAL_SRE_APT_PROXY_SERVER = 1700
    INTERNAL_SRE_CLAMAV_MIRROR = 1800
    INTERNAL_SRE_DATA_CONFIGURATION = 1900
    INTERNAL_SRE_DATA_DESIRED_STATE = 1910
    INTERNAL_SRE_DATA_PRIVATE = 1920
    INTERNAL_SRE_GUACAMOLE_CONTAINERS = 2000
    INTERNAL_SRE_GUACAMOLE_CONTAINERS_SUPPORT = 2100
    INTERNAL_SRE_IDENTITY_CONTAINERS = 2200
    INTERNAL_SRE_MONITORING_TOOLS = 2300
    INTERNAL_SRE_USER_SERVICES_CONTAINERS = 2400
    INTERNAL_SRE_USER_SERVICES_CONTAINERS_SUPPORT = 2500
    INTERNAL_SRE_USER_SERVICES_DATABASES = 2600
    INTERNAL_SRE_USER_SERVICES_SOFTWARE_REPOSITORIES = 2700
    INTERNAL_SRE_WORKSPACES = 2800
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
    RSTUDIO_DEB = ("download1.rstudio.org",)
    SOFTWARE_REPOSITORIES_PYTHON = (
        "files.pythonhosted.org",
        "pypi.org",
    )
    SOFTWARE_REPOSITORIES_R = ("cran.r-project.org",)
    SOFTWARE_REPOSITORIES = SOFTWARE_REPOSITORIES_PYTHON + SOFTWARE_REPOSITORIES_R
    UBUNTU_KEYSERVER = ("keyserver.ubuntu.com",)
    UBUNTU_SNAPCRAFT = (
        "api.snapcraft.io",
        "*.snapcraftcontent.com",
    )
    ALL = tuple(
        sorted(
            set(
                APT_REPOSITORIES
                + AZURE_DNS_ZONES
                + CLAMAV_UPDATES
                + MICROSOFT_GRAPH_API
                + MICROSOFT_LOGIN
                + RSTUDIO_DEB
                + SOFTWARE_REPOSITORIES_PYTHON
                + SOFTWARE_REPOSITORIES_R
                + UBUNTU_KEYSERVER
                + UBUNTU_SNAPCRAFT
            )
        )
    )


@verify(UNIQUE)
class Ports(str, Enum):
    AZURE_MONITORING = "514"
    DNS = "53"
    HKP = "11371"
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
