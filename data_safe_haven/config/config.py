"""Configuration file backed by blob storage"""

from __future__ import annotations

from pathlib import Path
from typing import Any, ClassVar

import yaml
from azure.keyvault.keys import KeyVaultKey
from pydantic import (
    BaseModel,
    Field,
    FieldSerializationInfo,
    ValidationError,
    field_serializer,
    field_validator,
)
from yaml import YAMLError

from data_safe_haven import __version__
from data_safe_haven.config.context_settings import Context
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.external import AzureApi
from data_safe_haven.functions import (
    alphanumeric,
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
    Fqdn,
    Guid,
    IpAddress,
    TimeZone,
)


class ConfigSectionAzure(BaseModel, validate_assignment=True):
    admin_group_id: Guid = Field(..., exclude=True)
    location: AzureLocation = Field(..., exclude=True)
    subscription_id: Guid
    tenant_id: Guid

    def __init__(self, context: Context, **kwargs: dict[Any, Any]):
        super().__init__(
            admin_group_id=context.admin_group_id, location=context.location, **kwargs
        )


class ConfigSectionPulumi(BaseModel, validate_assignment=True):
    storage_container_name: ClassVar[str] = "pulumi"
    encryption_key_name: ClassVar[str] = "pulumi-encryption-key"
    stacks: dict[str, str] = Field(..., default_factory=dict[str, str])


class ConfigSectionSHM(BaseModel, validate_assignment=True):
    aad_tenant_id: Guid
    admin_email_address: EmailAdress
    admin_ip_addresses: list[IpAddress]
    fqdn: Fqdn
    name: str = Field(..., exclude=True)
    timezone: TimeZone

    def __init__(self, context: Context, **kwargs: dict[Any, Any]):
        super().__init__(name=context.shm_name, **kwargs)

    def update(
        self,
        *,
        aad_tenant_id: str | None = None,
        admin_email_address: str | None = None,
        admin_ip_addresses: list[str] | None = None,
        fqdn: str | None = None,
        timezone: TimeZone | None = None,
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
    databases: list[DatabaseSystem] = Field(..., default_factory=list[DatabaseSystem])
    data_provider_ip_addresses: list[IpAddress] = Field(
        ..., default_factory=list[IpAddress]
    )
    index: int = Field(..., ge=0)
    remote_desktop: ConfigSubsectionRemoteDesktopOpts = Field(
        ..., default_factory=ConfigSubsectionRemoteDesktopOpts
    )
    workspace_skus: list[AzureVmSku] = Field(..., default_factory=list[AzureVmSku])
    research_user_ip_addresses: list[IpAddress] = Field(
        ..., default_factory=list[IpAddress]
    )
    software_packages: SoftwarePackageCategory = SoftwarePackageCategory.NONE

    @field_validator("databases")
    @classmethod
    def all_databases_must_be_unique(
        cls, v: list[DatabaseSystem]
    ) -> list[DatabaseSystem]:
        if len(v) != len(set(v)):
            msg = "all databases must be unique"
            raise ValueError(msg)
        return v

    @field_serializer("software_packages")
    def software_packages_serializer(
        self,
        packages: SoftwarePackageCategory,
        info: FieldSerializationInfo,  # noqa: ARG002
    ) -> str:
        return packages.value

    def update(
        self,
        *,
        data_provider_ip_addresses: list[IpAddress] | None = None,
        databases: list[DatabaseSystem] | None = None,
        workspace_skus: list[AzureVmSku] | None = None,
        software_packages: SoftwarePackageCategory | None = None,
        user_ip_addresses: list[IpAddress] | None = None,
    ) -> None:
        """Update SRE settings

        Args:
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

    def __init__(self, context: Context, **kwargs: dict[Any, Any]):
        super().__init__(deployment=context.name, **kwargs)


class Config(BaseModel, validate_assignment=True):
    azure: ConfigSectionAzure
    context: Context = Field(..., exclude=True)
    pulumi: ConfigSectionPulumi
    shm: ConfigSectionSHM
    sres: dict[str, ConfigSectionSRE] = Field(
        ..., default_factory=dict[str, ConfigSectionSRE]
    )
    tags: ConfigSectionTags = Field(..., exclude=True)

    _pulumi_encryption_key = None

    def __init__(self, context: Context, **kwargs: dict[Any, Any]):
        tags = ConfigSectionTags(context)
        super().__init__(context=context, tags=tags, **kwargs)

    @property
    def work_directory(self) -> Path:
        return self.context.work_directory

    @property
    def pulumi_encryption_key(self) -> KeyVaultKey:
        if not self._pulumi_encryption_key:
            azure_api = AzureApi(subscription_name=self.context.subscription_name)
            self._pulumi_encryption_key = azure_api.get_keyvault_key(
                key_name=self.pulumi.encryption_key_name,
                key_vault_name=self.context.key_vault_name,
            )
        return self._pulumi_encryption_key

    @property
    def pulumi_encryption_key_version(self) -> str:
        """ID for the Pulumi encryption key"""
        key_id: str = self.pulumi_encryption_key.id
        return key_id.split("/")[-1]

    @property
    def sre_names(self) -> list[str]:
        """Names of all SREs"""
        return list(self.sres.keys())

    def is_complete(self, *, require_sres: bool) -> bool:
        if require_sres:
            if not self.sres:
                return False
        if not all((self.azure, self.pulumi, self.shm, self.tags)):
            return False
        return True

    @staticmethod
    def sanitise_sre_name(name: str) -> str:
        return alphanumeric(name).lower()

    def sre(self, name: str) -> ConfigSectionSRE:
        """Return the config entry for this SRE, raising an exception if it does not exist"""
        if name not in self.sre_names:
            msg = f"SRE {name} does not exist"
            raise DataSafeHavenConfigError(msg)
        return self.sres[name]

    def remove_sre(self, name: str) -> None:
        """Remove SRE config section by name"""
        if name in self.sre_names:
            del self.sres[name]

    def add_stack(self, name: str, path: Path) -> None:
        """Add a Pulumi stack file to config"""
        if self.pulumi:
            with open(path, encoding="utf-8") as f_stack:
                pulumi_cfg = f_stack.read()
            self.pulumi.stacks[name] = b64encode(pulumi_cfg)

    def remove_stack(self, name: str) -> None:
        """Remove Pulumi stack section by name"""
        if self.pulumi:
            stacks = self.pulumi.stacks
            if name in stacks.keys():
                del stacks[name]

    def write_stack(self, name: str, path: Path) -> None:
        """Write a Pulumi stack file from config"""
        if self.pulumi:
            pulumi_cfg = b64decode(self.pulumi.stacks[name])
            with open(path, "w", encoding="utf-8") as f_stack:
                f_stack.write(pulumi_cfg)

    @classmethod
    def template(cls, context: Context) -> Config:
        # Create object without validation to allow "replace me" prompts
        return Config.model_construct(
            context=context,
            azure=ConfigSectionAzure.model_construct(
                subscription_id="Azure subscription ID",
                tenant_id="Azure tenant ID",
            ),
            pulumi=ConfigSectionPulumi(),
            shm=ConfigSectionSHM.model_construct(
                aad_tenant_id="Azure Active Directory tenant ID",
                admin_email_address="Admin email address",
                admin_ip_addresses=["Admin IP addresses"],
                fqdn="TRE domain name",
                timezone="Timezone",
            ),
        )

    @classmethod
    def from_yaml(cls, context: Context, config_yaml: str) -> Config:
        try:
            config_dict = yaml.safe_load(config_yaml)
        except YAMLError as exc:
            msg = f"Could not parse configuration as YAML.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc

        if not isinstance(config_dict, dict):
            msg = "Unable to parse configuration as a dict."
            raise DataSafeHavenConfigError(msg)

        # Add context for constructors that require it
        config_dict["context"] = context
        for section in ["azure", "shm"]:
            config_dict[section]["context"] = context

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
        return Config.from_yaml(context, config_yaml)

    def to_yaml(self) -> str:
        return yaml.dump(self.model_dump(), indent=2)

    def upload(self) -> None:
        """Upload config to Azure storage"""
        azure_api = AzureApi(subscription_name=self.context.subscription_name)
        azure_api.upload_blob(
            self.to_yaml(),
            self.context.config_filename,
            self.context.resource_group_name,
            self.context.storage_account_name,
            self.context.storage_container_name,
        )
