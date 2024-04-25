from __future__ import annotations

from typing import ClassVar, TypeVar

import yaml
from pydantic import BaseModel, ValidationError
from yaml import YAMLError

from data_safe_haven.context import Context
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.external import AzureApi

T = TypeVar("T", bound="ConfigClass")


class ConfigClass(BaseModel, validate_assignment=True):
    """Base class for configuration that can be written to Azure storage"""

    config_type: ClassVar[str] = "ConfigClass"
    filename: ClassVar[str] = "config.yaml"

    def to_yaml(self) -> str:
        """Write configuration to a YAML formatted string"""
        return yaml.dump(self.model_dump(mode="json"), indent=2)

    def upload(self, context: Context) -> None:
        """Upload configuration data to Azure storage"""
        azure_api = AzureApi(subscription_name=context.subscription_name)
        azure_api.upload_blob(
            self.to_yaml(),
            self.filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    @classmethod
    def from_yaml(cls: type[T], settings_yaml: str) -> T:
        """Construct configuration from a YAML string"""
        try:
            settings_dict = yaml.safe_load(settings_yaml)
        except YAMLError as exc:
            msg = f"Could not parse {cls.config_type} configuration as YAML.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc

        if not isinstance(settings_dict, dict):
            msg = f"Unable to parse {cls.config_type} configuration as a dict."
            raise DataSafeHavenConfigError(msg)

        try:
            return cls.model_validate(settings_dict)
        except ValidationError as exc:
            msg = f"Could not load {cls.config_type} configuration.\n{exc}"
            raise DataSafeHavenParameterError(msg) from exc

    @classmethod
    def from_remote(cls: type[T], context: Context) -> T:
        """Construct configuration from a YAML file in Azure storage"""
        azure_api = AzureApi(subscription_name=context.subscription_name)
        config_yaml = azure_api.download_blob(
            cls.filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )
        return cls.from_yaml(config_yaml)
