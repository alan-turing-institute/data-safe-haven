"""Sections for use in configuration files"""

from __future__ import annotations

from ipaddress import ip_network
from itertools import combinations

from pydantic import BaseModel, HttpUrl, PositiveInt, field_validator, model_validator

from data_safe_haven.config import LOGGING_LEVELS
from data_safe_haven.types import (
    AzureDataDiskSize,
    AzureLocation,
    AzurePremiumFileShareSize,
    AzureServiceTag,
    AzureVmSku,
    DatabaseSystem,
    EmailAddress,
    Fqdn,
    Guid,
    IpAddress,
    SafeString,
    SoftwarePackageCategory,
    TimeZone,
    UniqueList,
)

MONITORING_RETENTION_PERIOD_MAX = 730
MONITORING_RETENTION_PERIOD_MIN = 30


class ConfigSectionAzure(BaseModel, validate_assignment=True):
    location: AzureLocation
    subscription_id: Guid
    tenant_id: Guid


class ConfigSectionDockerHub(BaseModel, validate_assignment=True):
    access_token: SafeString
    username: SafeString


class ConfigSectionSHM(BaseModel, validate_assignment=True):
    admin_group_id: Guid
    entra_tenant_id: Guid
    fqdn: Fqdn


class ConfigSectionMonitoring(BaseModel, validate_assignment=True):
    log_level: SafeString = "info"
    retention_period: PositiveInt = 30
    sampling_interval: PositiveInt = 60

    @field_validator(
        "log_level",
    )
    @classmethod
    def ensure_log_level(cls, v: SafeString) -> SafeString:
        if v in LOGGING_LEVELS.keys():
            return v
        else:
            msg = "Logging level must be one of error, warn, info, debug or trace"
            raise ValueError(msg)

    @field_validator(
        "retention_period",
    )
    @classmethod
    def ensure_retention_period(cls, v: PositiveInt) -> PositiveInt:
        # Azure supports retention periods between 30 and 730 days inclusive. See:
        # https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/service-limits#log-analytics-workspaces
        if v >= MONITORING_RETENTION_PERIOD_MIN and v <= MONITORING_RETENTION_PERIOD_MAX:
            return v
        else:
            msg = "Retention period must be between 30 and 730 days (inclusive)"
            raise ValueError(msg)


class ConfigSubsectionRemoteDesktopOpts(BaseModel, validate_assignment=True):
    allow_copy: bool
    allow_paste: bool


class ConfigSubsectionStorageQuotaGB(BaseModel, validate_assignment=True):
    home: AzurePremiumFileShareSize
    shared: AzurePremiumFileShareSize
    data_disk: AzureDataDiskSize = 0
    os_disk: AzureDataDiskSize = 64


class ConfigSubsectionNexus(BaseModel, validate_assignment=True):
    persistent_quota_gb: PositiveInt


class ConfigSubsectionDnsSidecar(BaseModel, validate_assignment=True):
    cron_expression: str
    replica_timeout: PositiveInt
    retry_limit: int
    workload_maximum_count: int
    workload_minimum_count: int


class GitRepository(BaseModel, validate_assignment=True):
    repository_name: str
    repository_url: HttpUrl
    repository_auth_token: str


class ConfigSubsectionGiteaMirror(BaseModel, validate_assignment=True):
    repositories: list[GitRepository]


class ConfigSectionUserServices(BaseModel, validate_assignment=True):
    nexus: ConfigSubsectionNexus = ConfigSubsectionNexus(persistent_quota_gb=10)
    dns_sidecar: ConfigSubsectionDnsSidecar = ConfigSubsectionDnsSidecar(
        cron_expression="*/30 * * * *",
        replica_timeout=10 * 60,
        retry_limit=0,
        workload_maximum_count=2,
        workload_minimum_count=1,
    )
    gitea_mirror: ConfigSubsectionGiteaMirror = ConfigSubsectionGiteaMirror(
        repositories=[]
    )


class ConfigSectionSRE(BaseModel, validate_assignment=True):
    # Mutable objects can be used as default arguments in Pydantic:
    # https://docs.pydantic.dev/latest/concepts/models/#fields-with-non-hashable-default-values
    admin_email_address: EmailAddress
    admin_ip_addresses: list[IpAddress] = []
    allow_workspace_internet: bool = False
    databases: UniqueList[DatabaseSystem] = []
    data_provider_ip_addresses: list[IpAddress] = []
    monitoring: ConfigSectionMonitoring = ConfigSectionMonitoring()
    remote_desktop: ConfigSubsectionRemoteDesktopOpts
    research_user_ip_addresses: list[IpAddress] | AzureServiceTag = []
    storage_quota_gb: ConfigSubsectionStorageQuotaGB
    software_packages: SoftwarePackageCategory = SoftwarePackageCategory.NONE
    timezone: TimeZone = "Etc/UTC"
    workspace_skus: list[AzureVmSku] = []

    @field_validator(
        "admin_ip_addresses",
        mode="after",
    )
    @classmethod
    def ensure_non_overlapping(cls, v: list[IpAddress]) -> list[IpAddress]:
        for a, b in combinations(v, 2):
            a_ip, b_ip = ip_network(a), ip_network(b)
            if a_ip.overlaps(b_ip):
                msg = "IP addresses must not overlap."
                raise ValueError(msg)
        return v

    @field_validator(
        "data_provider_ip_addresses",
        "research_user_ip_addresses",
        mode="after",
    )
    @classmethod
    def ensure_non_overlapping_or_tag(
        cls, v: list[IpAddress] | AzureServiceTag
    ) -> list[IpAddress] | AzureServiceTag:
        if isinstance(v, list):
            return cls.ensure_non_overlapping(v)
        else:
            return v

    @model_validator(mode="after")
    def validate_internet_and_packages(self) -> ConfigSectionSRE:
        if (
            self.allow_workspace_internet
            and self.software_packages != SoftwarePackageCategory.ANY
        ):
            msg = "When `allow_workspace_internet` is `true`, `software_packages` must be `any`"
            raise ValueError(msg)
        return self
