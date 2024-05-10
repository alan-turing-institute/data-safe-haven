"""A YAMLSerialisableModel that can be serialised to and from Azure"""

from difflib import unified_diff
from typing import Any, ClassVar, TypeVar

from data_safe_haven.external import AzureApi

from .context_base import ContextBase
from .yaml_serialisable_model import YAMLSerialisableModel

T = TypeVar("T", bound="AzureSerialisableModel")


class AzureSerialisableModel(YAMLSerialisableModel):
    """Base class for configuration that can be written to Azure storage"""

    config_type: ClassVar[str] = "AzureSerialisableModel"
    filename: ClassVar[str] = "config.yaml"

    def diff(self, context: ContextBase) -> list[str]:
        azure_api = AzureApi(subscription_name=context.subscription_name)
        remote_yaml = azure_api.download_blob(
            self.filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

        local_yaml = self.to_yaml()

        return list(
            unified_diff(
                remote_yaml.split(),
                local_yaml.split(),
                fromfile="remote",
                tofile="local",
            )
        )

    @classmethod
    def from_remote(cls: type[T], context: ContextBase) -> T:
        """Construct an AzureSerialisableModel from a YAML file in Azure storage."""
        azure_api = AzureApi(subscription_name=context.subscription_name)
        config_yaml = azure_api.download_blob(
            cls.filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )
        return cls.from_yaml(config_yaml)

    @classmethod
    def from_remote_or_create(
        cls: type[T], context: ContextBase, **default_args: Any
    ) -> T:
        """
        Construct an AzureSerialisableModel from a YAML file in Azure storage, or from
        default arguments if no such file exists.
        """
        azure_api = AzureApi(subscription_name=context.subscription_name)
        if azure_api.blob_exists(
            cls.filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        ):
            return cls.from_remote(context)
        else:
            return cls(**default_args)

    def upload(self, context: ContextBase) -> None:
        """Serialise an AzureSerialisableModel to a YAML file in Azure storage."""
        azure_api = AzureApi(subscription_name=context.subscription_name)
        azure_api.upload_blob(
            self.to_yaml(),
            self.filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )
