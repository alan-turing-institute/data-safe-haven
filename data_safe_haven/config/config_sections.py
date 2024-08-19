"""Sections for use in configuration files"""

from __future__ import annotations

from ipaddress import ip_network
from itertools import combinations

from pydantic import BaseModel, field_validator

from data_safe_haven.types import (
    AzureLocation,
    AzurePremiumFileShareSize,
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


class ConfigSubsectionRemoteDesktopOpts(BaseModel, validate_assignment=True):
    allow_copy: bool
    allow_paste: bool


class ConfigSubsectionStorageQuotaGB(BaseModel, validate_assignment=True):
    home: AzurePremiumFileShareSize
    shared: AzurePremiumFileShareSize


class ConfigSectionSRE(BaseModel, validate_assignment=True):
    # Mutable objects can be used as default arguments in Pydantic:
    # https://docs.pydantic.dev/latest/concepts/models/#fields-with-non-hashable-default-values
    admin_email_address: EmailAddress
    admin_ip_addresses: list[IpAddress] = []
    databases: UniqueList[DatabaseSystem] = []
    data_provider_ip_addresses: list[IpAddress] = []
    remote_desktop: ConfigSubsectionRemoteDesktopOpts
    research_user_ip_addresses: list[IpAddress] = []
    storage_quota_gb: ConfigSubsectionStorageQuotaGB
    software_packages: SoftwarePackageCategory = SoftwarePackageCategory.NONE
    timezone: TimeZone = "Etc/UTC"
    workspace_skus: list[AzureVmSku] = []

    @field_validator(
        "admin_ip_addresses",
        "data_provider_ip_addresses",
        "research_user_ip_addresses",
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
