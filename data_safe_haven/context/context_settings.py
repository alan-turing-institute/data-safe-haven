"""Load global and local settings from dotfiles"""

# For postponed evaluation of annotations https://peps.python.org/pep-0563
from __future__ import (
    annotations,
)

from pathlib import Path
from typing import ClassVar

import yaml
from azure.keyvault.keys import KeyVaultKey
from pydantic import BaseModel, Field, ValidationError, model_validator
from yaml import YAMLError

from data_safe_haven import __version__
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.external import AzureApi
from data_safe_haven.functions import alphanumeric
from data_safe_haven.utility import LoggingSingleton, config_dir
from data_safe_haven.utility.annotated_types import (
    AzureLocation,
    AzureLongName,
    Guid,
)


class Context(BaseModel, validate_assignment=True):
    admin_group_id: Guid
    location: AzureLocation
    name: str
    subscription_name: AzureLongName
    storage_container_name: ClassVar[str] = "config"
    pulumi_storage_container_name: ClassVar[str] = "pulumi"
    pulumi_encryption_key_name: ClassVar[str] = "pulumi-encryption-key"

    _pulumi_encryption_key = None

    @property
    def tags(self) -> dict[str, str]:
        return {
            "deployment": self.name,
            "deployed by": "Python",
            "project": "Data Safe Haven",
            "version": __version__,
        }

    @property
    def shm_name(self) -> str:
        return alphanumeric(self.name).lower()

    @property
    def work_directory(self) -> Path:
        return config_dir() / self.shm_name

    @property
    def resource_group_name(self) -> str:
        return f"shm-{self.shm_name}-rg-context"

    @property
    def storage_account_name(self) -> str:
        # maximum of 24 characters allowed
        return f"shm{self.shm_name[:14]}context"

    @property
    def key_vault_name(self) -> str:
        return f"shm-{self.shm_name[:9]}-kv-context"

    @property
    def managed_identity_name(self) -> str:
        return f"shm-{self.shm_name}-identity-reader-context"

    @property
    def pulumi_backend_url(self) -> str:
        return f"azblob://{self.pulumi_storage_container_name}"

    @property
    def pulumi_encryption_key(self) -> KeyVaultKey:
        if not self._pulumi_encryption_key:
            azure_api = AzureApi(subscription_name=self.subscription_name)
            self._pulumi_encryption_key = azure_api.get_keyvault_key(
                key_name=self.pulumi_encryption_key_name,
                key_vault_name=self.key_vault_name,
            )
        return self._pulumi_encryption_key

    @property
    def pulumi_encryption_key_version(self) -> str:
        """ID for the Pulumi encryption key"""
        key_id: str = self.pulumi_encryption_key.id
        return key_id.split("/")[-1]

    @property
    def pulumi_secrets_provider_url(self) -> str:
        return f"azurekeyvault://{self.key_vault_name}.vault.azure.net/keys/{self.pulumi_encryption_key_name}/{self.pulumi_encryption_key_version}"

    def to_yaml(self) -> str:
        return yaml.dump(self.model_dump(), indent=2)


class ContextSettings(BaseModel, validate_assignment=True):
    """Load global and local settings from dotfiles with structure like the following

    selected: acme_deployment
    contexts:
        acme_deployment:
            name: Acme Deployment
            admin_group_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
            location: uksouth
            subscription_name: Data Safe Haven (Acme)
        ...
    """

    selected_: str | None = Field(..., alias="selected")
    contexts: dict[str, Context]
    logger: ClassVar[LoggingSingleton] = LoggingSingleton()

    @model_validator(mode="after")
    def ensure_selected_is_valid(self) -> ContextSettings:
        if self.selected is not None:
            if self.selected not in self.available:
                msg = f"Selected context '{self.selected}' is not defined."
                raise ValueError(msg)
        return self

    @staticmethod
    def default_config_file_path() -> Path:
        return config_dir() / "contexts.yaml"

    @property
    def selected(self) -> str | None:
        return self.selected_

    @selected.setter
    def selected(self, context_name: str | None) -> None:
        if context_name in self.available or context_name is None:
            self.selected_ = context_name
            self.logger.info(f"Switched context to '{context_name}'.")
        else:
            msg = f"Context '{context_name}' is not defined."
            raise DataSafeHavenParameterError(msg)

    @property
    def context(self) -> Context | None:
        if self.selected is None:
            return None
        else:
            return self.contexts[self.selected]

    def assert_context(self) -> Context:
        if context := self.context:
            return context
        else:
            msg = "No context selected"
            raise DataSafeHavenConfigError(msg)

    @property
    def available(self) -> list[str]:
        return list(self.contexts.keys())

    def update(
        self,
        *,
        admin_group_id: str | None = None,
        location: str | None = None,
        name: str | None = None,
        subscription_name: str | None = None,
    ) -> None:
        context = self.assert_context()

        if admin_group_id:
            self.logger.debug(
                f"Updating '[green]{admin_group_id}[/]' to '{admin_group_id}'."
            )
            context.admin_group_id = admin_group_id
        if location:
            self.logger.debug(f"Updating '[green]{location}[/]' to '{location}'.")
            context.location = location
        if name:
            self.logger.debug(f"Updating '[green]{name}[/]' to '{name}'.")
            context.name = name
        if subscription_name:
            self.logger.debug(
                f"Updating '[green]{subscription_name}[/]' to '{subscription_name}'."
            )
            context.subscription_name = subscription_name

    def add(
        self,
        *,
        key: str,
        name: str,
        admin_group_id: str,
        location: str,
        subscription_name: str,
    ) -> None:
        # Ensure context is not already present
        if key in self.available:
            msg = f"A context with key '{key}' is already defined."
            raise DataSafeHavenParameterError(msg)

        self.contexts[key] = Context(
            name=name,
            admin_group_id=admin_group_id,
            location=location,
            subscription_name=subscription_name,
        )

    def remove(self, key: str) -> None:
        if key not in self.available:
            msg = f"No context with key '{key}'."
            raise DataSafeHavenParameterError(msg)

        del self.contexts[key]

        # Prevent having a deleted context selected
        if key == self.selected:
            self.selected = None

    @classmethod
    def from_yaml(cls, settings_yaml: str) -> ContextSettings:
        try:
            settings_dict = yaml.safe_load(settings_yaml)
        except YAMLError as exc:
            msg = f"Could not parse context settings as YAML.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc

        if not isinstance(settings_dict, dict):
            msg = "Unable to parse context settings as a dict."
            raise DataSafeHavenConfigError(msg)

        try:
            return ContextSettings.model_validate(settings_dict)
        except ValidationError as exc:
            msg = f"Could not load context settings.\n{exc}"
            raise DataSafeHavenParameterError(msg) from exc

    @classmethod
    def from_file(cls, config_file_path: Path | None = None) -> ContextSettings:
        if config_file_path is None:
            config_file_path = cls.default_config_file_path()
        cls.logger.info(
            f"Reading project settings from '[green]{config_file_path}[/]'."
        )
        try:
            with open(config_file_path, encoding="utf-8") as f_yaml:
                settings_yaml = f_yaml.read()
            return cls.from_yaml(settings_yaml)
        except FileNotFoundError as exc:
            msg = f"Could not find file {config_file_path}.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc

    def to_yaml(self) -> str:
        return yaml.dump(self.model_dump(by_alias=True), indent=2)

    def write(self, config_file_path: Path | None = None) -> None:
        """Write settings to YAML file"""
        if config_file_path is None:
            config_file_path = self.default_config_file_path()
        # Create the parent directory if it does not exist then write YAML
        config_file_path.parent.mkdir(parents=True, exist_ok=True)

        with open(config_file_path, "w", encoding="utf-8") as f_yaml:
            f_yaml.write(self.to_yaml())
        self.logger.info(f"Saved context settings to '[green]{config_file_path}[/]'.")