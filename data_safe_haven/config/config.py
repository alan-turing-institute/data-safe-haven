"""Configuration file backed by blob storage"""
# Standard library imports
import pathlib
from collections import defaultdict
from contextlib import suppress
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

# Third party imports
import chili
import yaml

# Local imports
from data_safe_haven import __version__
from data_safe_haven.exceptions import DataSafeHavenAzureException
from data_safe_haven.external import AzureApi
from data_safe_haven.functions import (
    alphanumeric,
    b64decode,
    b64encode,
    validate_aad_guid,
    validate_azure_location,
    validate_azure_vm_sku,
    validate_email_address,
    validate_ip_address,
    validate_timezone,
)
from data_safe_haven.utility import SoftwarePackageCategory, YamlType
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
            raise TypeError(
                f"Invalid value for 'admin_group_id' ({self.admin_group_id}).\n{str(exc)}"
            )
        try:
            validate_azure_location(self.location)
        except Exception as exc:
            raise TypeError(
                f"Invalid value for 'location' ({self.location}).\n{str(exc)}"
            )
        try:
            validate_aad_guid(self.subscription_id)
        except Exception as exc:
            raise TypeError(
                f"Invalid value for 'subscription_id' ({self.subscription_id}).\n{str(exc)}"
            )
        try:
            validate_aad_guid(self.tenant_id)
        except Exception as exc:
            raise TypeError(
                f"Invalid value for 'tenant_id' ({self.tenant_id}).\n{str(exc)}"
            )

    def to_dict(self) -> Dict[str, str]:
        self.validate()
        return chili.encode(self)  # type: ignore


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
            raise TypeError(
                f"Invalid value for 'key_vault_name' ({self.key_vault_name})."
            )
        if not self.managed_identity_name:
            raise TypeError(
                f"Invalid value for 'managed_identity_name' ({self.managed_identity_name})."
            )
        if not self.resource_group_name:
            raise TypeError(
                f"Invalid value for 'resource_group_name' ({self.resource_group_name})."
            )
        if not self.storage_account_name:
            raise TypeError(
                f"Invalid value for 'storage_account_name' ({self.storage_account_name})."
            )
        if not self.storage_container_name:
            raise TypeError(
                f"Invalid value for 'storage_container_name' ({self.storage_container_name})."
            )

    def to_dict(self) -> Dict[str, str]:
        self.validate()
        return chili.encode(self)  # type: ignore


@dataclass
class ConfigSectionPulumi:
    encryption_key_id: str = ""
    encryption_key_name: str = "pulumi-encryption-key"
    stacks: Dict[str, str] = field(default_factory=dict)
    storage_container_name: str = "pulumi"

    def validate(self) -> None:
        """Validate input parameters"""
        if not isinstance(self.encryption_key_id, str) or not self.encryption_key_id:
            raise TypeError(
                f"Invalid value for 'encryption_key_id' ({self.encryption_key_id})."
            )

    def to_dict(self) -> Dict[str, Any]:
        self.validate()
        return chili.encode(self)  # type: ignore


@dataclass
class ConfigSectionSHM:
    aad_tenant_id: str = ""
    admin_email_address: str = ""
    admin_ip_addresses: List[str] = field(default_factory=list)
    fqdn: str = ""
    name: str = ""
    timezone: str = ""

    def validate(self) -> None:
        """Validate input parameters"""
        try:
            validate_aad_guid(self.aad_tenant_id)
        except Exception as exc:
            raise TypeError(
                f"Invalid value for 'aad_tenant_id' ({self.aad_tenant_id}).\n{str(exc)}"
            )
        try:
            validate_email_address(self.admin_email_address)
        except Exception as exc:
            raise TypeError(
                f"Invalid value for 'admin_email_address' ({self.admin_email_address}).\n{str(exc)}"
            )
        try:
            for ip in self.admin_ip_addresses:
                validate_ip_address(ip)
        except Exception as exc:
            raise TypeError(
                f"Invalid value for 'admin_ip_addresses' ({self.admin_ip_addresses}).\n{str(exc)}"
            )
        if not isinstance(self.fqdn, str) or not self.fqdn:
            raise TypeError(f"Invalid value for 'fqdn' ({self.fqdn}).")
        if not isinstance(self.name, str) or not self.name:
            raise TypeError(f"Invalid value for 'name' ({self.name}).")
        try:
            validate_timezone(self.timezone)
        except Exception as exc:
            raise TypeError(
                f"Invalid value for 'timezone' ({self.timezone}).\n{str(exc)}"
            )

    def to_dict(self) -> Dict[str, Any]:
        self.validate()
        return chili.encode(self)  # type: ignore


@dataclass
class ConfigSectionSRE:
    @dataclass
    class ConfigSectionRemoteDesktopOpts:
        allow_copy: bool = False
        allow_paste: bool = False

        def validate(self) -> None:
            """Validate input parameters"""
            if not isinstance(self.allow_copy, bool):
                raise TypeError(f"Invalid value for 'allow_copy' ({self.allow_copy}).")
            if not isinstance(self.allow_paste, bool):
                raise TypeError(
                    f"Invalid value for 'allow_paste' ({self.allow_paste})."
                )

        def to_dict(self) -> Dict[str, bool]:
            self.validate()
            return chili.encode(self)  # type: ignore

    @dataclass
    class ConfigSectionResearchDesktopOpts:
        sku: str = ""

        def validate(self) -> None:
            """Validate input parameters"""
            try:
                validate_azure_vm_sku(self.sku)
            except Exception as exc:
                raise TypeError(f"Invalid value for 'sku' ({self.sku}).\n{str(exc)}")

        def to_dict(self) -> Dict[str, str]:
            self.validate()
            return chili.encode(self)  # type: ignore

    data_provider_ip_addresses: List[str] = field(default_factory=list)
    index: int = 0
    remote_desktop: ConfigSectionRemoteDesktopOpts = field(
        default_factory=ConfigSectionRemoteDesktopOpts
    )
    # NB. we cannot use defaultdict here until https://github.com/python/cpython/pull/32056 is included in the Python version we are using
    research_desktops: Dict[str, ConfigSectionResearchDesktopOpts] = field(
        default_factory=dict
    )
    research_user_ip_addresses: List[str] = field(default_factory=list)
    software_packages: SoftwarePackageCategory = SoftwarePackageCategory.NONE

    def add_research_desktop(self, name: str):
        self.research_desktops[
            name
        ] = ConfigSectionSRE.ConfigSectionResearchDesktopOpts()

    def validate(self) -> None:
        """Validate input parameters"""
        try:
            for ip in self.data_provider_ip_addresses:
                validate_ip_address(ip)
        except Exception as exc:
            raise TypeError(
                f"Invalid value for 'data_provider_ip_addresses' ({self.data_provider_ip_addresses}).\n{str(exc)}"
            )
        self.remote_desktop.validate()
        try:
            for ip in self.research_user_ip_addresses:
                validate_ip_address(ip)
        except Exception as exc:
            raise TypeError(
                f"Invalid value for 'research_user_ip_addresses' ({self.research_user_ip_addresses}).\n{str(exc)}"
            )

    def to_dict(self) -> Dict[str, Any]:
        self.validate()
        return chili.encode(self)  # type: ignore


@dataclass
class ConfigSectionTags:
    deployment: str = ""
    deployed_by: str = "Python"
    project: str = "Data Safe Haven"
    version: str = __version__

    def validate(self) -> None:
        """Validate input parameters"""
        if not self.deployment:
            raise TypeError(f"Invalid value for 'deployment' ({self.deployment}).")

    def to_dict(self) -> Dict[str, str]:
        self.validate()
        return chili.encode(self)  # type: ignore


class Config:
    def __init__(self):
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
        # Config sections
        self.azure_api_: Optional[AzureApi] = None
        self.azure_: Optional[ConfigSectionAzure] = None
        self.backend_: Optional[ConfigSectionBackend] = None
        self.pulumi_: Optional[ConfigSectionPulumi] = None
        self.shm_: Optional[ConfigSectionSHM] = None
        self.tags_: Optional[ConfigSectionTags] = None
        self.sres: Dict[str, ConfigSectionSRE] = defaultdict(ConfigSectionSRE)
        # Attempt to load from blob storage
        with suppress(DataSafeHavenAzureException):
            self.download()

    @property
    def azure_api(self) -> AzureApi:
        """Load AzureAPI on demand

        Returns:
            AzureApi: An initialised AzureApi object
        """
        if not self.azure_api_:
            self.azure_api_ = AzureApi(
                subscription_name=self.subscription_name,
            )
        return self.azure_api_

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
        contents = {}
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
        return str(yaml.dump(contents, indent=2))

    def read_stack(self, name: str, path: pathlib.Path):
        """Add a Pulumi stack file to config"""
        with open(path, "r", encoding="utf-8") as f_stack:
            stack_yaml = yaml.safe_load(f_stack)
        self.pulumi.stacks[name] = b64encode(yaml.dump(stack_yaml))

    def write_stack(self, name: str, path: pathlib.Path):
        """Write a Pulumi stack file from config"""
        stack_yaml = yaml.dump(b64decode(self.pulumi.stacks[name]), indent=2)
        with open(path, "w", encoding="utf-8") as f_stack:
            f_stack.writelines(stack_yaml)

    def download(self):
        """Download config from Azure storage and interpret it"""
        self.from_yaml(
            yaml.safe_load(
                self.azure_api.download_blob(
                    self.filename,
                    self.backend_resource_group_name,
                    self.backend_storage_account_name,
                    self.backend_storage_container_name,
                )
            )
        )

    def from_yaml(self, yaml_input: YamlType) -> None:
        """Construct a config object from YAML"""
        if "azure" in yaml_input:
            self.azure_ = chili.decode(yaml_input["azure"], ConfigSectionAzure)
        if "backend" in yaml_input:
            self.backend_ = chili.decode(yaml_input["backend"], ConfigSectionBackend)
        if "pulumi" in yaml_input:
            self.pulumi_ = chili.decode(yaml_input["pulumi"], ConfigSectionPulumi)
        if "shm" in yaml_input:
            self.shm_ = chili.decode(yaml_input["shm"], ConfigSectionSHM)
        if "sre" in yaml_input:
            for sre_name, sre_details in dict(yaml_input["sre"]).items():
                self.sres[sre_name] = chili.decode(sre_details, ConfigSectionSRE)

    def upload(self):
        """Upload config to Azure storage"""
        self.azure_api.upload_blob(
            str(self),
            self.filename,
            self.backend_resource_group_name,
            self.backend_storage_account_name,
            self.backend_storage_container_name,
        )
