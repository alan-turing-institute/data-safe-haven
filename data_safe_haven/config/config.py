"""Configuration file backed by blob storage"""
import pathlib
from collections import defaultdict
from collections.abc import Callable
from contextlib import suppress
from dataclasses import dataclass, field
from functools import partial
from typing import Any, ClassVar

import chili
import yaml
from yaml.parser import ParserError

from data_safe_haven import __version__
from data_safe_haven.exceptions import DataSafeHavenAzureError, DataSafeHavenConfigError
from data_safe_haven.external import AzureApi
from data_safe_haven.functions import (
    alphanumeric,
    as_dict,
    b64decode,
    b64encode,
    validate_aad_guid,
    validate_azure_location,
    validate_azure_vm_sku,
    validate_email_address,
    validate_ip_address,
    validate_non_empty_string,
    validate_string_length,
    validate_timezone,
    validate_type,
)
from data_safe_haven.utility import LoggingSingleton, SoftwarePackageCategory

from .backend_settings import BackendSettings


class Validator:
    validation_functions: ClassVar[dict[str, Callable[[Any], Any]]] = {}

    def validate(self) -> None:
        """Validate instance attributes.

        Validation fails if the provided validation function raises an exception.
        """
        for attr_name, validator in self.validation_functions.items():
            try:
                validator(getattr(self, attr_name))
            except Exception as exc:
                msg = f"Invalid value for '{attr_name}' ({getattr(self, attr_name)}).\n{exc}"
                raise DataSafeHavenConfigError(msg) from exc


class ConfigSection(Validator):
    def to_dict(self) -> dict[str, Any]:
        """Dictionary representation of this object."""
        self.validate()
        return as_dict(chili.encode(self))


@dataclass
class ConfigSectionAzure(ConfigSection):
    admin_group_id: str = ""
    location: str = ""
    subscription_id: str = ""
    tenant_id: str = ""

    validation_functions = {  # noqa: RUF012
        "admin_group_id": validate_aad_guid,
        "location": validate_azure_location,
        "subscription_id": validate_aad_guid,
        "tenant_id": validate_aad_guid,
    }


@dataclass
class ConfigSectionBackend(ConfigSection):
    key_vault_name: str = ""
    managed_identity_name: str = ""
    resource_group_name: str = ""
    storage_account_name: str = ""
    storage_container_name: str = ""

    validation_functions = {  # noqa: RUF012
        "key_vault_name": partial(validate_string_length, min_length=3, max_length=24),
        "managed_identity_name": partial(
            validate_string_length, min_length=1, max_length=64
        ),
        "resource_group_name": partial(
            validate_string_length, min_length=1, max_length=64
        ),
        "storage_account_name": partial(
            validate_string_length, min_length=1, max_length=24
        ),
        "storage_container_name": partial(
            validate_string_length, min_length=1, max_length=64
        ),
    }


@dataclass
class ConfigSectionPulumi(ConfigSection):
    encryption_key_id: str = ""
    encryption_key_name: str = "pulumi-encryption-key"
    stacks: dict[str, str] = field(default_factory=dict)
    storage_container_name: str = "pulumi"

    validation_functions = {  # noqa: RUF012
        "encryption_key_id": validate_non_empty_string,
        "encryption_key_name": validate_non_empty_string,
        "stacks": lambda stacks: isinstance(stacks, dict),
        "storage_container_name": validate_non_empty_string,
    }


@dataclass
class ConfigSectionSHM(ConfigSection):
    aad_tenant_id: str = ""
    admin_email_address: str = ""
    admin_ip_addresses: list[str] = field(default_factory=list)
    fqdn: str = ""
    name: str = ""
    timezone: str = ""

    validation_functions = {  # noqa: RUF012
        "aad_tenant_id": validate_aad_guid,
        "admin_email_address": validate_email_address,
        "admin_ip_addresses": lambda ips: [validate_ip_address(ip) for ip in ips],
        "fqdn": validate_non_empty_string,
        "name": validate_non_empty_string,
        "timezone": validate_timezone,
    }

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


@dataclass
class ConfigSectionSRE(ConfigSection):
    @dataclass
    class ConfigSubsectionRemoteDesktopOpts(Validator):
        allow_copy: bool = False
        allow_paste: bool = False

        validation_functions = {  # noqa: RUF012
            "allow_copy": partial(validate_type, type_=bool),
            "allow_paste": partial(validate_type, type_=bool),
        }

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

    @dataclass
    class ConfigSubsectionResearchDesktopOpts(Validator):
        sku: str = ""

        validation_functions = {"sku": validate_azure_vm_sku}  # noqa: RUF012

    data_provider_ip_addresses: list[str] = field(default_factory=list)
    index: int = 0
    remote_desktop: ConfigSubsectionRemoteDesktopOpts = field(
        default_factory=ConfigSubsectionRemoteDesktopOpts
    )
    # NB. unless https://github.com/python/cpython/pull/32056 is included in the Python
    # version we are using, we cannot use defaultdict here.
    research_desktops: dict[str, ConfigSubsectionResearchDesktopOpts] = field(
        default_factory=dict
    )
    research_user_ip_addresses: list[str] = field(default_factory=list)
    software_packages: SoftwarePackageCategory = SoftwarePackageCategory.NONE

    validation_functions = {  # noqa: RUF012
        "data_provider_ip_addresses": lambda ips: [
            validate_ip_address(ip) for ip in ips
        ],
        "index": lambda idx: isinstance(idx, int) and idx >= 0,
        "remote_desktop": lambda dsktop: dsktop.validate(),
        "research_desktops": lambda dsktops: [
            dsktop.validate() for dsktop in dsktops.values()
        ],
        "research_user_ip_addresses": lambda ips: [
            validate_ip_address(ip) for ip in ips
        ],
        "software_packages": lambda pkg: isinstance(pkg, SoftwarePackageCategory),
    }

    def update(
        self,
        *,
        allow_copy: bool | None = None,
        allow_paste: bool | None = None,
        data_provider_ip_addresses: list[str] | None = None,
        research_desktops: list[str] | None = None,
        software_packages: SoftwarePackageCategory | None = None,
        user_ip_addresses: list[str] | None = None,
    ) -> None:
        """Update SRE settings

        Args:
            allow_copy: Allow/deny copying text out of the SRE
            allow_paste: Allow/deny pasting text into the SRE
            data_provider_ip_addresses: List of IP addresses belonging to data providers
            research_desktops: List of VM SKUs for research desktops
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
        # Pass allow_copy and allow_paste to remote desktop
        self.remote_desktop.update(allow_copy=allow_copy, allow_paste=allow_paste)
        # Set research desktop SKUs
        if research_desktops:
            if sorted(research_desktops) != sorted(self.research_desktops.keys()):
                self.research_desktops.clear()
                for idx, vm_sku in enumerate(research_desktops):
                    self.research_desktops[
                        f"workspace-{idx:02d}"
                    ] = ConfigSectionSRE.ConfigSubsectionResearchDesktopOpts(sku=vm_sku)
        logger.info(
            f"[bold]Research desktops[/] will be [green]{list(self.research_desktops.keys())}[/]."
        )
        # Select which software packages can be installed by users
        if software_packages:
            self.software_packages = software_packages
        logger.info(
            f"[bold]Software packages[/] from [green]{self.software_packages}[/] sources will be installable."
        )
        # Set user IP addresses
        if user_ip_addresses:
            self.research_user_ip_addresses = user_ip_addresses
        logger.info(
            f"[bold]IP addresses used by users[/] will be [green]{self.research_user_ip_addresses}[/]."
        )


@dataclass
class ConfigSectionTags(ConfigSection):
    deployment: str = ""
    deployed_by: str = "Python"
    project: str = "Data Safe Haven"
    version: str = __version__

    validation_functions = {  # noqa: RUF012
        "deployment": validate_non_empty_string,
        "deployed_by": validate_non_empty_string,
        "project": validate_non_empty_string,
        "version": validate_non_empty_string,
    }


class Config:
    def __init__(self) -> None:
        # Initialise config sections
        self.azure_: ConfigSectionAzure | None = None
        self.backend_: ConfigSectionBackend | None = None
        self.pulumi_: ConfigSectionPulumi | None = None
        self.shm_: ConfigSectionSHM | None = None
        self.tags_: ConfigSectionTags | None = None
        self.sres: dict[str, ConfigSectionSRE] = defaultdict(ConfigSectionSRE)
        # Read backend settings
        settings = BackendSettings()
        self.name = settings.name
        self.subscription_name = settings.subscription_name
        self.azure.location = settings.location
        self.azure.admin_group_id = settings.admin_group_id
        self.backend_storage_container_name = "config"
        # Set derived names
        self.shm_name_ = alphanumeric(self.name).lower()
        self.filename = f"config-{self.shm_name_}.yaml"
        self.backend_resource_group_name = f"shm-{self.shm_name_}-rg-backend"
        self.backend_storage_account_name = (
            f"shm{self.shm_name_[:14]}backend"  # maximum of 24 characters allowed
        )
        self.work_directory = settings.config_directory / self.shm_name_
        self.azure_api = AzureApi(subscription_name=self.subscription_name)
        # Attempt to load YAML dictionary from blob storage
        yaml_input = {}
        with suppress(DataSafeHavenAzureError, ParserError):
            yaml_input = yaml.safe_load(
                self.azure_api.download_blob(
                    self.filename,
                    self.backend_resource_group_name,
                    self.backend_storage_account_name,
                    self.backend_storage_container_name,
                )
            )
        # Attempt to decode each config section
        if yaml_input:
            if "azure" in yaml_input:
                self.azure_ = chili.decode(yaml_input["azure"], ConfigSectionAzure)
            if "backend" in yaml_input:
                self.backend_ = chili.decode(
                    yaml_input["backend"], ConfigSectionBackend
                )
            if "pulumi" in yaml_input:
                self.pulumi_ = chili.decode(yaml_input["pulumi"], ConfigSectionPulumi)
            if "shm" in yaml_input:
                self.shm_ = chili.decode(yaml_input["shm"], ConfigSectionSHM)
            if "sre" in yaml_input:
                for sre_name, sre_details in dict(yaml_input["sre"]).items():
                    self.sres[sre_name] = chili.decode(sre_details, ConfigSectionSRE)

    @property
    def azure(self) -> ConfigSectionAzure:
        if not self.azure_:
            self.azure_ = ConfigSectionAzure()
        return self.azure_

    @property
    def backend(self) -> ConfigSectionBackend:
        if not self.backend_:
            self.backend_ = ConfigSectionBackend(
                key_vault_name=f"shm-{self.shm_name_[:9]}-kv-backend",
                managed_identity_name=f"shm-{self.shm_name_}-identity-reader-backend",
                resource_group_name=self.backend_resource_group_name,
                storage_account_name=self.backend_storage_account_name,
                storage_container_name=self.backend_storage_container_name,
            )
        return self.backend_

    @property
    def pulumi(self) -> ConfigSectionPulumi:
        if not self.pulumi_:
            self.pulumi_ = ConfigSectionPulumi()
        return self.pulumi_

    @property
    def shm(self) -> ConfigSectionSHM:
        if not self.shm_:
            self.shm_ = ConfigSectionSHM(name=self.shm_name_)
        return self.shm_

    @property
    def tags(self) -> ConfigSectionTags:
        if not self.tags_:
            self.tags_ = ConfigSectionTags(deployment=self.name)
        return self.tags_

    def __str__(self) -> str:
        """String representation of the Config object"""
        contents: dict[str, Any] = {}
        if self.azure_:
            contents["azure"] = self.azure.to_dict()
        if self.backend_:
            contents["backend"] = self.backend.to_dict()
        if self.pulumi_:
            contents["pulumi"] = self.pulumi.to_dict()
        if self.shm_:
            contents["shm"] = self.shm.to_dict()
        if self.sres:
            contents["sre"] = {k: v.to_dict() for k, v in self.sres.items()}
        if self.tags:
            contents["tags"] = self.tags.to_dict()
        return str(yaml.dump(contents, indent=2))

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

    def upload(self) -> None:
        """Upload config to Azure storage"""
        self.azure_api.upload_blob(
            str(self),
            self.filename,
            self.backend_resource_group_name,
            self.backend_storage_account_name,
            self.backend_storage_container_name,
        )

    def write_stack(self, name: str, path: pathlib.Path) -> None:
        """Write a Pulumi stack file from config"""
        pulumi_cfg = b64decode(self.pulumi.stacks[name])
        with open(path, "w", encoding="utf-8") as f_stack:
            f_stack.write(pulumi_cfg)
