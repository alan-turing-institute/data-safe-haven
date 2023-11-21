"""Configuration file backed by blob storage"""
from __future__ import annotations

import pathlib

import yaml
from pydantic import BaseModel, Field, ValidationError, computed_field
from yaml import YAMLError

from data_safe_haven import __version__
from data_safe_haven.config.context_settings import Context
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.external import AzureApi
from data_safe_haven.functions import (
    b64decode,
    b64encode,
)
from data_safe_haven.utility import (
    DatabaseSystem,
    LoggingSingleton,
    SoftwarePackageCategory,
)
from data_safe_haven.utility.annotated_types import (
    AzureLocation,
    AzureVmSku,
    EmailAdress,
    Guid,
    IpAddress,
    TimeZone,
)


class ConfigSectionAzure(BaseModel, validate_assignment=True):
    admin_group_id: Guid
    location: AzureLocation
    subscription_id: Guid
    tenant_id: Guid


class ConfigSectionPulumi(BaseModel, validate_assignment=True):
    encryption_key_name: str = "pulumi-encryption-key"
    encryption_key_version: str
    stacks: dict[str, str] = Field(default_factory=dict)
    storage_container_name: str = "pulumi"


class ConfigSectionSHM(BaseModel, validate_assignment=True):
    aad_tenant_id: Guid
    admin_email_address: EmailAdress
    admin_ip_addresses: list[IpAddress]
    fqdn: str
    name: str
    timezone: TimeZone

    def update(
        self,
        *,
        aad_tenant_id: str | None = None,
        admin_email_address: str | None = None,
        admin_ip_addresses: list[str] | None = None,
        fqdn: str | None = None,
        timezone: str | None = None,
    ) -> None:
        """Update SHM settings

        Args:
            aad_tenant_id: AzureAD tenant containing users
            admin_email_address: Email address shared by all administrators
            admin_ip_addresses: List of IP addresses belonging to administrators
            fqdn: Fully-qualified domain name to use for this SHM
            timezone: Timezone in pytz format (eg. Europe/London)
        """
        logger = LoggingSingleton()
        # Set AzureAD tenant ID
        if aad_tenant_id:
            self.aad_tenant_id = aad_tenant_id
        logger.info(
            f"[bold]AzureAD tenant ID[/] will be [green]{self.aad_tenant_id}[/]."
        )
        # Set admin email address
        if admin_email_address:
            self.admin_email_address = admin_email_address
        logger.info(
            f"[bold]Admin email address[/] will be [green]{self.admin_email_address}[/]."
        )
        # Set admin IP addresses
        if admin_ip_addresses:
            self.admin_ip_addresses = admin_ip_addresses
        logger.info(
            f"[bold]IP addresses used by administrators[/] will be [green]{self.admin_ip_addresses}[/]."
        )
        # Set fully-qualified domain name
        if fqdn:
            self.fqdn = fqdn
        logger.info(
            f"[bold]Fully-qualified domain name[/] will be [green]{self.fqdn}[/]."
        )
        # Set timezone
        if timezone:
            self.timezone = timezone
        logger.info(f"[bold]Timezone[/] will be [green]{self.timezone}[/].")


class ConfigSubsectionRemoteDesktopOpts(BaseModel, validate_assignment=True):
    allow_copy: bool = False
    allow_paste: bool = False

    def update(
        self, *, allow_copy: bool | None = None, allow_paste: bool | None = None
    ) -> None:
        """Update SRE remote desktop settings

        Args:
            allow_copy: Allow/deny copying text out of the SRE
            allow_paste: Allow/deny pasting text into the SRE
        """
        # Set whether copying text out of the SRE is allowed
        if allow_copy:
            self.allow_copy = allow_copy
        LoggingSingleton().info(
            f"[bold]Copying text out of the SRE[/] will be [green]{'allowed' if self.allow_copy else 'forbidden'}[/]."
        )
        # Set whether pasting text into the SRE is allowed
        if allow_paste:
            self.allow_paste = allow_paste
        LoggingSingleton().info(
            f"[bold]Pasting text into the SRE[/] will be [green]{'allowed' if self.allow_paste else 'forbidden'}[/]."
        )


class ConfigSectionSRE(BaseModel, validate_assignment=True):
    databases: list[DatabaseSystem]
    data_provider_ip_addresses: list[IpAddress]
    index: int = Field(ge=0)
    remote_desktop: ConfigSubsectionRemoteDesktopOpts
    workspace_skus: list[AzureVmSku]
    research_user_ip_addresses: list[IpAddress]
    software_packages: SoftwarePackageCategory = SoftwarePackageCategory.NONE

    def update(
        self,
        *,
        allow_copy: bool | None = None,
        allow_paste: bool | None = None,
        data_provider_ip_addresses: list[str] | None = None,
        databases: list[DatabaseSystem] | None = None,
        workspace_skus: list[str] | None = None,
        software_packages: SoftwarePackageCategory | None = None,
        user_ip_addresses: list[str] | None = None,
    ) -> None:
        """Update SRE settings

        Args:
            allow_copy: Allow/deny copying text out of the SRE
            allow_paste: Allow/deny pasting text into the SRE
            databases: List of database systems to deploy
            data_provider_ip_addresses: List of IP addresses belonging to data providers
            workspace_skus: List of VM SKUs for workspaces
            software_packages: Whether to allow packages from external repositories
            user_ip_addresses: List of IP addresses belonging to users
        """
        logger = LoggingSingleton()
        # Set data provider IP addresses
        if data_provider_ip_addresses:
            self.data_provider_ip_addresses = data_provider_ip_addresses
        logger.info(
            f"[bold]IP addresses used by data providers[/] will be [green]{self.data_provider_ip_addresses}[/]."
        )
        # Set which databases to deploy
        if databases:
            self.databases = sorted(set(databases))
            if len(self.databases) != len(databases):
                logger.warning("Discarding duplicate values for 'database'.")
        logger.info(
            f"[bold]Databases available to users[/] will be [green]{[database.value for database in self.databases]}[/]."
        )
        # Pass allow_copy and allow_paste to remote desktop
        self.remote_desktop.update(allow_copy=allow_copy, allow_paste=allow_paste)
        # Set research desktop SKUs
        if workspace_skus:
            self.workspace_skus = workspace_skus
        logger.info(f"[bold]Workspace SKUs[/] will be [green]{self.workspace_skus}[/].")
        # Select which software packages can be installed by users
        if software_packages:
            self.software_packages = software_packages
        logger.info(
            f"[bold]Software packages[/] from [green]{self.software_packages.value}[/] sources will be installable."
        )
        # Set user IP addresses
        if user_ip_addresses:
            self.research_user_ip_addresses = user_ip_addresses
        logger.info(
            f"[bold]IP addresses used by users[/] will be [green]{self.research_user_ip_addresses}[/]."
        )


class ConfigSectionTags(BaseModel, validate_assignment=True):
    deployment: str
    deployed_by: str = "Python"
    project: str = "Data Safe Haven"
    version: str = __version__


class Config(BaseModel, validate_assignment=True):
    azure: ConfigSectionAzure | None = None
    context: Context
    pulumi: ConfigSectionPulumi | None = None
    shm: ConfigSectionSHM | None = None
    tags: ConfigSectionTags | None = None
    sres: dict[str, ConfigSectionSRE] | None = None

    @computed_field
    def work_directory(self) -> str:
        return self.context.work_directory

    def read_stack(self, name: str, path: pathlib.Path) -> None:
        """Add a Pulumi stack file to config"""
        with open(path, encoding="utf-8") as f_stack:
            pulumi_cfg = f_stack.read()
        self.pulumi.stacks[name] = b64encode(pulumi_cfg)

    def remove_sre(self, name: str) -> None:
        """Remove SRE config section by name"""
        if name in self.sres.keys():
            del self.sres[name]

    def remove_stack(self, name: str) -> None:
        """Remove Pulumi stack section by name"""
        if name in self.pulumi.stacks.keys():
            del self.pulumi.stacks[name]

    def sre(self, name: str) -> ConfigSectionSRE:
        """Return the config entry for this SRE creating it if it does not exist"""
        if name not in self.sres.keys():
            highest_index = max([0] + [sre.index for sre in self.sres.values()])
            self.sres[name].index = highest_index + 1
        return self.sres[name]

    @classmethod
    def from_yaml(cls, config_yaml: str) -> Config:
        try:
            config_dict = yaml.safe_load(config_yaml)
        except YAMLError as exc:
            msg = f"Could not parse configuration as YAML.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc

        if not isinstance(config_dict, dict):
            msg = "Unable to parse configuration as a dict."
            raise DataSafeHavenConfigError(msg)

        try:
            return Config.model_validate(config_dict)
        except ValidationError as exc:
            msg = f"Could not load configuration.\n{exc}"
            raise DataSafeHavenParameterError(msg) from exc

    @classmethod
    def from_remote(cls, context: Context) -> Config:
        azure_api = AzureApi(subscription_name=context.subscription_name)
        config_yaml = azure_api.download_blob(
            context.config_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )
        return Config.from_yaml(config_yaml)

    def upload(self) -> None:
        """Upload config to Azure storage"""
        self.azure_api.upload_blob(
            yaml.dump(self.model_dump, indent=2),
            self.context.config_filename,
            self.context.resource_group_name,
            self.context.storage_account_name,
            self.context.storage_container_name,
        )

    def write_stack(self, name: str, path: pathlib.Path) -> None:
        """Write a Pulumi stack file from config"""
        pulumi_cfg = b64decode(self.pulumi.stacks[name])
        with open(path, "w", encoding="utf-8") as f_stack:
            f_stack.write(pulumi_cfg)
