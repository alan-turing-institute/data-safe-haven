"""Helper class for Azure fileshares"""

from contextlib import suppress

from azure.core.exceptions import ResourceNotFoundError
from azure.mgmt.storage import StorageManagementClient
from azure.storage.fileshare import ShareDirectoryClient, ShareFileClient

from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.external import AzureApi


class AzureFileShare:
    """Interface for Azure fileshares"""

    def __init__(
        self,
        storage_account_name: str,
        storage_account_resource_group_name: str,
        subscription_name: str,
        share_name: str,
    ):
        self.azure_api = AzureApi(subscription_name)
        self.storage_client_: StorageManagementClient | None = None
        self.storage_account_key_: str | None = None
        self.storage_account_name: str = storage_account_name
        self.resource_group_name: str = storage_account_resource_group_name
        self.share_name: str = share_name

    @property
    def storage_client(self) -> StorageManagementClient:
        if not self.storage_client_:
            self.storage_client_ = StorageManagementClient(
                self.azure_api.credential, self.azure_api.subscription_id
            )
        return self.storage_client_

    @property
    def storage_account_key(self) -> str:
        if not self.storage_account_key_:
            storage_account_keys = [
                k.value
                for k in self.azure_api.get_storage_account_keys(
                    self.resource_group_name, self.storage_account_name
                )
                if isinstance(k.value, str)
            ]
            if not storage_account_keys:
                msg = f"Could not load key values for storage account {self.storage_account_name}."
                raise DataSafeHavenAzureError(msg)
            self.storage_account_key_ = storage_account_keys[0]
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
            msg = f"Failed to upload data to [green]{target}[/] in [green]{self.share_name}[/]."
            raise DataSafeHavenAzureError(msg) from exc

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
            msg = f"Failed to delete file [green]{target}[/] in [green]{self.share_name}[/]."
            raise DataSafeHavenAzureError(msg) from exc

    @staticmethod
    def file_exists(file_client: ShareFileClient) -> bool:
        with suppress(ResourceNotFoundError):
            file_client.get_file_properties()
            return True
        return False

    def file_client(
        self,
        file_name: str,
        directory: str | None = None,
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
