"""A YAMLSerialisableModel that can be serialised to and from Azure"""

from typing import Any, ClassVar, TypeVar

from data_safe_haven.exceptions import (
    DataSafeHavenAzureError,
    DataSafeHavenAzureStorageError,
    DataSafeHavenTypeError,
)
from data_safe_haven.external import AzureSdk

from .context_base import ContextBase
from .yaml_serialisable_model import YAMLSerialisableModel

T = TypeVar("T", bound="AzureSerialisableModel")


class AzureSerialisableModel(YAMLSerialisableModel):
    """Base class for configuration that can be written to Azure storage"""

    config_type: ClassVar[str] = "AzureSerialisableModel"
    default_filename: ClassVar[str] = "config.yaml"

    @classmethod
    def from_remote(
        cls: type[T], context: ContextBase, *, filename: str | None = None
    ) -> T:
        """
        Construct an AzureSerialisableModel from a YAML file in Azure storage.

        Raises:
            DataSafeHavenAzureError: if the file cannot be loaded
            DataSafeHavenAzureStorageError: if the storage account does not exist
        """
        try:
            azure_sdk = AzureSdk(subscription_name=context.subscription_name)
            config_yaml = azure_sdk.download_blob(
                filename or cls.default_filename,
                context.resource_group_name,
                context.storage_account_name,
                context.storage_container_name,
            )
            return cls.from_yaml(config_yaml)
        except DataSafeHavenAzureStorageError as exc:
            msg = f"Storage account '{context.storage_account_name}' does not exist."
            raise DataSafeHavenAzureStorageError(msg) from exc
        except DataSafeHavenAzureError as exc:
            msg = f"Could not load file '{filename or cls.default_filename}' from Azure storage."
            raise DataSafeHavenAzureError(msg) from exc
        except DataSafeHavenTypeError as exc:
            msg = f"'{filename or cls.default_filename}' does not contain a valid {cls.config_type} configuration."
            raise DataSafeHavenTypeError(msg) from exc

    @classmethod
    def from_remote_or_create(
        cls: type[T], context: ContextBase, **default_args: Any
    ) -> T:
        """
        Construct an AzureSerialisableModel from a YAML file in Azure storage, or from
        default arguments if no such file exists.
        """
        if cls.remote_exists(context):
            return cls.from_remote(context)
        else:
            return cls(**default_args)

    @classmethod
    def remote_exists(
        cls: type[T], context: ContextBase, *, filename: str | None = None
    ) -> bool:
        """Check whether a remote instance of this model exists."""
        azure_sdk = AzureSdk(subscription_name=context.subscription_name)
        if azure_sdk.storage_exists(context.storage_account_name):
            return azure_sdk.blob_exists(
                filename or cls.default_filename,
                context.resource_group_name,
                context.storage_account_name,
                context.storage_container_name,
            )
        else:
            return False

    def remote_yaml_diff(
        self: T, context: ContextBase, *, filename: str | None = None
    ) -> list[str]:
        """
        Determine the diff of YAML output from the remote model to `self`.

        The diff is given in unified diff format.
        """
        remote_model = self.from_remote(context, filename=filename)

        return self.yaml_diff(remote_model, from_name="remote", to_name="local")

    def upload(self: T, context: ContextBase, *, filename: str | None = None) -> None:
        """Serialise an AzureSerialisableModel to a YAML file in Azure storage."""
        azure_sdk = AzureSdk(subscription_name=context.subscription_name)
        azure_sdk.upload_blob(
            self.to_yaml(),
            filename or self.default_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )
