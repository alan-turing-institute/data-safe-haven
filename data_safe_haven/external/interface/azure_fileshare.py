"""Helper class for Azure fileshares"""
# Standard library imports
from contextlib import suppress
from typing import Any, Optional

# Third party imports
from azure.core.exceptions import ResourceNotFoundError
from azure.mgmt.storage import StorageManagementClient
from azure.storage.fileshare import ShareDirectoryClient, ShareFileClient

# Local imports
from data_safe_haven.exceptions import DataSafeHavenAzureException
from data_safe_haven.mixins import AzureMixin


class AzureFileShare(AzureMixin):
    """Interface for Azure fileshares"""

    def __init__(
        self,
        storage_account_name: str,
        storage_account_resource_group_name: str,
        subscription_name: str,
        share_name: str,
        *args: Any,
        **kwargs: Any,
    ):
        kwargs[
            "subscription_name"
        ] = subscription_name  # workaround for erroneous 'multiple values for keyword' mypy warning
        super().__init__(*args, **kwargs)
        self.storage_client_: Optional[StorageManagementClient] = None
        self.storage_account_key_: Optional[str] = None
        self.storage_account_name: str = storage_account_name
        self.resource_group_name: str = storage_account_resource_group_name
        self.share_name: str = share_name

    @property
    def storage_client(self) -> StorageManagementClient:
        if not self.storage_client_:
            self.storage_client_ = StorageManagementClient(
                self.credential, self.subscription_id
            )
        return self.storage_client_

    @property
    def storage_account_key(self) -> str:
        if not self.storage_account_key_:
            storage_keys = self.storage_client.storage_accounts.list_keys(
                self.resource_group_name, self.storage_account_name
            )
            if not storage_keys.keys:
                raise DataSafeHavenAzureException(
                    f"Could not load keys for storage account {self.storage_account_name}."
                )
            self.storage_account_key_ = [key.value for key in storage_keys.keys][0]
        return self.storage_account_key_

    def upload(self, destination_path: str, file_contents: str) -> None:
        """Upload file contents to the target storage account location."""
        target = "UNKNOWN"
        try:
            tokens = destination_path.split("/")
            directory = "/".join(tokens[:-1])
            target = tokens[-1]
            file_client = self.file_client(
                target,
                directory=directory,
            )
            file_client.upload_file(file_contents.encode("utf-8"))
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to upload data to <fg=green>{target}</> in <fg=green>{self.share_name}</>."
            ) from exc

    def delete(self, destination_path: str) -> None:
        """Delete a file from the target storage account"""
        target = "UNKNOWN"
        try:
            tokens = destination_path.split("/")
            directory = "/".join(tokens[:-1])
            target = tokens[-1]
            file_client = self.file_client(
                target,
                directory=directory,
            )
            if self.file_exists(file_client):
                file_client.delete_file()
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to delete file <fg=green>{target}</> in <fg=green>{self.share_name}</>."
            ) from exc

    @staticmethod
    def file_exists(file_client: ShareFileClient) -> bool:
        with suppress(ResourceNotFoundError):
            file_client.get_file_properties()
            return True
        return False

    def file_client(
        self,
        file_name: str,
        directory: Optional[str] = None,
    ) -> ShareFileClient:
        if directory:
            directory_client = ShareDirectoryClient(
                account_url=f"https://{self.storage_account_name}.file.core.windows.net",
                share_name=self.share_name,
                directory_path=directory,
                credential=self.storage_account_key,
            )
            if not directory_client.exists():
                directory_client.create_directory()
            return directory_client.get_file_client(file_name)
        return ShareFileClient(
            account_url=f"https://{self.storage_account_name}.file.core.windows.net",
            share_name=self.share_name,
            file_path=file_name,
            credential=self.storage_account_key,
        )
