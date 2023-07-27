"""Configuration file backed by blob storage"""
import pathlib
from collections import defaultdict
from contextlib import suppress
from dataclasses import dataclass, field
from typing import Any

import chili
import yaml
from yaml.parser import ParserError

from data_safe_haven import __version__
from data_safe_haven.exceptions import DataSafeHavenAzureError
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
    validate_timezone,
)
from data_safe_haven.utility import LoggingSingleton, SoftwarePackageCategory

from .backend_settings import BackendSettings


@dataclass
class ConfigSectionAzure:
    admin_group_id: str = ""
    location: str = ""
    subscription_id: str = ""
    tenant_id: str = ""

    def validate(self) -> None:
        """Validate input parameters"""
        try:
            validate_aad_guid(self.admin_group_id)
        except Exception as exc:
            msg = f"Invalid value for 'admin_group_id' ({self.admin_group_id}).\n{exc}"
            raise ValueError(msg) from exc
        try:
            validate_azure_location(self.location)
        except Exception as exc:
            msg = f"Invalid value for 'location' ({self.location}).\n{exc}"
            raise ValueError(msg) from exc
        try:
            validate_aad_guid(self.subscription_id)
        except Exception as exc:
            msg = (
                f"Invalid value for 'subscription_id' ({self.subscription_id}).\n{exc}"
            )
            raise ValueError(msg) from exc
        try:
            validate_aad_guid(self.tenant_id)
        except Exception as exc:
            msg = f"Invalid value for 'tenant_id' ({self.tenant_id}).\n{exc}"
            raise ValueError(msg) from exc

    def to_dict(self) -> dict[str, str]:
        self.validate()
        return as_dict(chili.encode(self))


@dataclass
class ConfigSectionBackend:
    key_vault_name: str = ""
    managed_identity_name: str = ""
    resource_group_name: str = ""
    storage_account_name: str = ""
    storage_container_name: str = ""

    def validate(self) -> None:
        """Validate input parameters"""
        if not self.key_vault_name:
            msg = f"Invalid value for 'key_vault_name' ({self.key_vault_name})."
            raise ValueError(msg)
        if not self.managed_identity_name:
            msg = f"Invalid value for 'managed_identity_name' ({self.managed_identity_name})."
            raise ValueError(msg)
        if not self.resource_group_name:
            msg = (
                f"Invalid value for 'resource_group_name' ({self.resource_group_name})."
            )
            raise ValueError(msg)
        if not self.storage_account_name:
            msg = f"Invalid value for 'storage_account_name' ({self.storage_account_name})."
            raise ValueError(msg)
        if not self.storage_container_name:
            msg = f"Invalid value for 'storage_container_name' ({self.storage_container_name})."
            raise ValueError(msg)

    def to_dict(self) -> dict[str, str]:
        self.validate()
        return as_dict(chili.encode(self))


@dataclass
class ConfigSectionPulumi:
    encryption_key_id: str = ""
    encryption_key_name: str = "pulumi-encryption-key"
    stacks: dict[str, str] = field(default_factory=dict)
    storage_container_name: str = "pulumi"

    def validate(self) -> None:
        """Validate input parameters"""
        if not isinstance(self.encryption_key_id, str) or not self.encryption_key_id:
            msg = f"Invalid value for 'encryption_key_id' ({self.encryption_key_id})."
            raise ValueError(msg)

    def to_dict(self) -> dict[str, Any]:
        self.validate()
        return as_dict(chili.encode(self))


@dataclass
class ConfigSectionSHM:
    aad_tenant_id: str = ""
    admin_email_address: str = ""
    admin_ip_addresses: list[str] = field(default_factory=list)
    fqdn: str = ""
    name: str = ""
    timezone: str = ""

    def validate(self) -> None:
        """Validate input parameters"""
        try:
            validate_aad_guid(self.aad_tenant_id)
        except Exception as exc:
            msg = f"Invalid value for 'aad_tenant_id' ({self.aad_tenant_id}).\n{exc}"
            raise ValueError(msg) from exc
        try:
            validate_email_address(self.admin_email_address)
        except Exception as exc:
            msg = f"Invalid value for 'admin_email_address' ({self.admin_email_address}).\n{exc}"
            raise ValueError(msg) from exc
        try:
            for ip in self.admin_ip_addresses:
                validate_ip_address(ip)
        except Exception as exc:
            msg = f"Invalid value for 'admin_ip_addresses' ({self.admin_ip_addresses}).\n{exc}"
            raise ValueError(msg) from exc
        if not isinstance(self.fqdn, str) or not self.fqdn:
            msg = f"Invalid value for 'fqdn' ({self.fqdn})."
            raise ValueError(msg)
        if not isinstance(self.name, str) or not self.name:
            msg = f"Invalid value for 'name' ({self.name})."
            raise ValueError(msg)
        try:
            validate_timezone(self.timezone)
        except Exception as exc:
            msg = f"Invalid value for 'timezone' ({self.timezone}).\n{exc}"
            raise ValueError(msg) from exc

    def to_dict(self) -> dict[str, Any]:
        self.validate()
        return as_dict(chili.encode(self))


@dataclass
class ConfigSectionSRE:
    @dataclass
    class ConfigSectionRemoteDesktopOpts:
        allow_copy: bool = False
        allow_paste: bool = False

        def update(
            self, *, allow_copy: bool | None = None, allow_paste: bool | None = None
        ) -> None:
            # Set whether copying text out of the SRE is allowed
            if allow_copy:
                LoggingSingleton().debug(
                    f"[bold]Copying text out of the SRE[/] was previously [green]{'allowed' if self.allow_copy else 'forbidden'}[/]."
                )
                self.allow_copy = allow_copy
            LoggingSingleton().info(
                f"[bold]Copying text out of the SRE[/] will be [green]{'allowed' if self.allow_copy else 'forbidden'}[/]."
            )
            # Set whether pasting text into the SRE is allowed
            if allow_paste:
                LoggingSingleton().debug(
                    f"[bold]Pasting text into the SRE[/] was previously [green]{'allowed' if self.allow_paste else 'forbidden'}[/]."
                )
                self.allow_paste = allow_paste
            LoggingSingleton().info(
                f"[bold]Pasting text into the SRE[/] will be [green]{'allowed' if self.allow_paste else 'forbidden'}[/]."
            )

        def validate(self) -> None:
            """Validate input parameters"""
            if not isinstance(self.allow_copy, bool):
                msg = f"Invalid value for 'allow_copy' ({self.allow_copy})."
                raise ValueError(msg)
            if not isinstance(self.allow_paste, bool):
                msg = f"Invalid value for 'allow_paste' ({self.allow_paste})."
                raise ValueError(msg)

        def to_dict(self) -> dict[str, bool]:
            self.validate()
            return as_dict(chili.encode(self))

    @dataclass
    class ConfigSectionResearchDesktopOpts:
        sku: str = ""

        def validate(self) -> None:
            """Validate input parameters"""
            try:
                validate_azure_vm_sku(self.sku)
            except Exception as exc:
                msg = f"Invalid value for 'sku' ({self.sku}).\n{exc}"
                raise ValueError(msg) from exc

        def to_dict(self) -> dict[str, str]:
            self.validate()
            return as_dict(chili.encode(self))

    data_provider_ip_addresses: list[str] = field(default_factory=list)
    index: int = 0
    remote_desktop: ConfigSectionRemoteDesktopOpts = field(
        default_factory=ConfigSectionRemoteDesktopOpts
    )
    # NB. we cannot use defaultdict here until
    # https://github.com/python/cpython/pull/32056 is included in the Python
    # version we are using
    research_desktops: dict[str, ConfigSectionResearchDesktopOpts] = field(
        default_factory=dict
    )
    research_user_ip_addresses: list[str] = field(default_factory=list)
    software_packages: SoftwarePackageCategory = SoftwarePackageCategory.NONE

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
        # Set data provider IP addresses
        if data_provider_ip_addresses:
            LoggingSingleton().debug(
                f"[bold]IP addresses used by data providers[/] were previously [green]{self.data_provider_ip_addresses}[/]."
            )
            self.data_provider_ip_addresses = data_provider_ip_addresses
        LoggingSingleton().info(
            f"[bold]IP addresses used by data providers[/] will be [green]{self.data_provider_ip_addresses}[/]."
        )
        # Pass allow_copy and allow_paste to remote desktop
        self.remote_desktop.update(allow_copy=allow_copy, allow_paste=allow_paste)
        # Set research desktop SKUs
        if research_desktops:
            if sorted(research_desktops) != sorted(self.research_desktops.keys()):
                LoggingSingleton().debug(
                    f"[bold]Research desktops[/] were previously [green]{list(self.research_desktops.keys())}[/]."
                )
                self.research_desktops.clear()
                for idx, vm_sku in enumerate(research_desktops):
                    self.research_desktops[
                        f"workspace-{idx:02d}"
                    ] = ConfigSectionSRE.ConfigSectionResearchDesktopOpts(sku=vm_sku)
        LoggingSingleton().info(
            f"[bold]Research desktops[/] will be [green]{list(self.research_desktops.keys())}[/]."
        )
        # Select which software packages can be installed by users
        if software_packages:
            LoggingSingleton().debug(
                f"[bold]Software packages[/] from [green]{self.software_packages}[/] sources were previously installable."
            )
            self.software_packages = software_packages
        LoggingSingleton().info(
            f"[bold]Software packages[/] from [green]{self.software_packages}[/] sources will be installable."
        )
        # Set user IP addresses
        if user_ip_addresses:
            LoggingSingleton().debug(
                f"[bold]IP addresses used by users[/] were previously [green]{self.research_user_ip_addresses}[/]."
            )
            self.research_user_ip_addresses = user_ip_addresses
        LoggingSingleton().info(
            f"[bold]IP addresses used by users[/] will be [green]{self.research_user_ip_addresses}[/]."
        )

    def validate(self) -> None:
        """Validate input parameters"""
        try:
            for ip in self.data_provider_ip_addresses:
                validate_ip_address(ip)
        except Exception as exc:
            msg = f"Invalid value for 'data_provider_ip_addresses' ({self.data_provider_ip_addresses}).\n{exc}"
            raise ValueError(msg) from exc
        self.remote_desktop.validate()
        for research_desktop in self.research_desktops.values():
            research_desktop.validate()
        try:
            for ip in self.research_user_ip_addresses:
                validate_ip_address(ip)
        except Exception as exc:
            msg = f"Invalid value for 'research_user_ip_addresses' ({self.research_user_ip_addresses}).\n{exc}"
            raise ValueError(msg) from exc

    def to_dict(self) -> dict[str, Any]:
        self.validate()
        return as_dict(chili.encode(self))


@dataclass
class ConfigSectionTags:
    deployment: str = ""
    deployed_by: str = "Python"
    project: str = "Data Safe Haven"
    version: str = __version__

    def validate(self) -> None:
        """Validate input parameters"""
        if not self.deployment:
            msg = f"Invalid value for 'deployment' ({self.deployment})."
            raise ValueError(msg)

    def to_dict(self) -> dict[str, str]:
        self.validate()
        return as_dict(chili.encode(self))


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

    def write_stack(self, name: str, path: pathlib.Path) -> None:
        """Write a Pulumi stack file from config"""
        pulumi_cfg = b64decode(self.pulumi.stacks[name])
        with open(path, "w", encoding="utf-8") as f_stack:
            f_stack.write(pulumi_cfg)

    def upload(self) -> None:
        """Upload config to Azure storage"""
        self.azure_api.upload_blob(
            str(self),
            self.filename,
            self.backend_resource_group_name,
            self.backend_storage_account_name,
            self.backend_storage_container_name,
        )
