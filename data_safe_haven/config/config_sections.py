"""Sections for use in configuration files"""

from __future__ import annotations

from pydantic import (
    BaseModel,
    Field,
)

from data_safe_haven.external import AzureCliSingleton
from data_safe_haven.logging import get_logger
from data_safe_haven.types import (
    AzureLocation,
    AzureVmSku,
    DatabaseSystem,
    EmailAddress,
    EntraGroupName,
    Fqdn,
    Guid,
    IpAddress,
    SoftwarePackageCategory,
    TimeZone,
    UniqueList,
)


class ConfigSectionAzure(BaseModel, validate_assignment=True):
    location: AzureLocation
    subscription_id: Guid
    tenant_id: Guid


class ConfigSectionSHM(BaseModel, validate_assignment=True):
    admin_group_name: EntraGroupName
    entra_tenant_id: Guid
    fqdn: Fqdn

    @property
    def admin_group_id(self) -> str:
        return AzureCliSingleton().group_id_from_name(self.admin_group_name)

    def update(
        self,
        *,
        admin_group_name: str | None = None,
        entra_tenant_id: str | None = None,
        fqdn: str | None = None,
    ) -> None:
        """Update SHM settings

        Args:
            admin_group_name: Name of a security group that contains all Azure infrastructure admins.
            entra_tenant_id: Tenant ID for the Entra ID used to manage TRE users
            fqdn: Fully-qualified domain name to use for this TRE
        """
        logger = get_logger()
        # Set admin group name
        if admin_group_name:
            self.admin_group_name = admin_group_name
        logger.debug(
            f"[bold]Admin group name[/] will be [green]{self.admin_group_name}[/]."
        )
        # Set Entra tenant ID
        if entra_tenant_id:
            self.entra_tenant_id = entra_tenant_id
        logger.debug(
            f"[bold]Entra tenant ID[/] will be [green]{self.entra_tenant_id}[/]."
        )
        # Set fully-qualified domain name
        if fqdn:
            self.fqdn = fqdn
        logger.debug(
            f"[bold]Fully-qualified domain name[/] will be [green]{self.fqdn}[/]."
        )


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
        logger = get_logger()
        # Set whether copying text out of the SRE is allowed
        if allow_copy:
            self.allow_copy = allow_copy
        logger.debug(
            f"[bold]Copying text out of the SRE[/] will be [green]{'allowed' if self.allow_copy else 'forbidden'}[/]."
        )
        # Set whether pasting text into the SRE is allowed
        if allow_paste:
            self.allow_paste = allow_paste
        logger.debug(
            f"[bold]Pasting text into the SRE[/] will be [green]{'allowed' if self.allow_paste else 'forbidden'}[/]."
        )


class ConfigSectionSRE(BaseModel, validate_assignment=True):
    admin_email_address: EmailAddress
    admin_ip_addresses: list[IpAddress] = Field(..., default_factory=list[IpAddress])
    databases: UniqueList[DatabaseSystem] = Field(
        ..., default_factory=list[DatabaseSystem]
    )
    data_provider_ip_addresses: list[IpAddress] = Field(
        ..., default_factory=list[IpAddress]
    )
    remote_desktop: ConfigSubsectionRemoteDesktopOpts = Field(
        ..., default_factory=ConfigSubsectionRemoteDesktopOpts
    )
    research_user_ip_addresses: list[IpAddress] = Field(
        ..., default_factory=list[IpAddress]
    )
    software_packages: SoftwarePackageCategory = SoftwarePackageCategory.NONE
    timezone: TimeZone = "Etc/UTC"
    workspace_skus: list[AzureVmSku] = Field(..., default_factory=list[AzureVmSku])

    def update(
        self,
        *,
        admin_email_address: str | None = None,
        admin_ip_addresses: list[str] | None = None,
        data_provider_ip_addresses: list[IpAddress] | None = None,
        databases: list[DatabaseSystem] | None = None,
        software_packages: SoftwarePackageCategory | None = None,
        timezone: TimeZone | None = None,
        user_ip_addresses: list[IpAddress] | None = None,
        workspace_skus: list[AzureVmSku] | None = None,
    ) -> None:
        """Update SRE settings

        Args:
            admin_email_address: Email address shared by all administrators
            admin_ip_addresses: List of IP addresses belonging to administrators
            databases: List of database systems to deploy
            data_provider_ip_addresses: List of IP addresses belonging to data providers
            software_packages: Whether to allow packages from external repositories
            timezone: Timezone in pytz format (eg. Europe/London)
            user_ip_addresses: List of IP addresses belonging to users
            workspace_skus: List of Azure VM SKUs - see cloudprice.net for list of valid SKUs
        """
        logger = get_logger()
        # Set admin email address
        if admin_email_address:
            self.admin_email_address = admin_email_address
        logger.debug(
            f"[bold]Admin email address[/] will be [green]{self.admin_email_address}[/]."
        )
        # Set admin IP addresses
        if admin_ip_addresses:
            self.admin_ip_addresses = admin_ip_addresses
        logger.debug(
            f"[bold]IP addresses used by administrators[/] will be [green]{self.admin_ip_addresses}[/]."
        )
        # Set data provider IP addresses
        if data_provider_ip_addresses:
            self.data_provider_ip_addresses = data_provider_ip_addresses
        logger.debug(
            f"[bold]IP addresses used by data providers[/] will be [green]{self.data_provider_ip_addresses}[/]."
        )
        # Set which databases to deploy
        if databases:
            self.databases = sorted(set(databases))
            if len(self.databases) != len(databases):
                logger.warning("Discarding duplicate values for 'database'.")
        logger.debug(
            f"[bold]Databases available to users[/] will be [green]{[database.value for database in self.databases]}[/]."
        )
        # Select which software packages can be installed by users
        if software_packages:
            self.software_packages = software_packages
        logger.debug(
            f"[bold]Software packages[/] from [green]{self.software_packages.value}[/] sources will be installable."
        )
        # Set timezone
        if timezone:
            self.timezone = timezone
        logger.info(f"[bold]Timezone[/] will be [green]{self.timezone}[/].")
        # Set user IP addresses
        if user_ip_addresses:
            self.research_user_ip_addresses = user_ip_addresses
        logger.debug(
            f"[bold]IP addresses used by users[/] will be [green]{self.research_user_ip_addresses}[/]."
        )
        # Set workspace desktop SKUs
        if workspace_skus:
            self.workspace_skus = workspace_skus
        logger.debug(
            f"[bold]Workspace SKUs[/] will be [green]{self.workspace_skus}[/]."
        )
