"""Sections for use in configuration files"""

from __future__ import annotations

from pydantic import (
    BaseModel,
    Field,
)

from data_safe_haven.types import (
    AzureLocation,
    AzureVmSku,
    DatabaseSystem,
    EmailAddress,
    Fqdn,
    GiteaServers,
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
    allow_copy: bool = False
    allow_paste: bool = False


class ConfigSectionSRE(BaseModel, validate_assignment=True):
    admin_email_address: EmailAddress
    admin_ip_addresses: list[IpAddress] = Field(..., default_factory=list[IpAddress])
    databases: UniqueList[DatabaseSystem] = Field(
        ..., default_factory=list[DatabaseSystem]
    )
    data_provider_ip_addresses: list[IpAddress] = Field(
        ..., default_factory=list[IpAddress]
    )
    gitea_servers: GiteaServers = GiteaServers.INTERNAL
    remote_desktop: ConfigSubsectionRemoteDesktopOpts = Field(
        ..., default_factory=ConfigSubsectionRemoteDesktopOpts
    )
    research_user_ip_addresses: list[IpAddress] = Field(
        ..., default_factory=list[IpAddress]
    )
    software_packages: SoftwarePackageCategory = SoftwarePackageCategory.NONE
    timezone: TimeZone = "Etc/UTC"
    workspace_skus: list[AzureVmSku] = Field(..., default_factory=list[AzureVmSku])
