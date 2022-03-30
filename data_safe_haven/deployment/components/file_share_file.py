# Standard library imports
import binascii
import os
from typing import Optional

# Third party imports
from azure.core.exceptions import ResourceNotFoundError
from azure.storage.fileshare import ShareFileClient, ShareDirectoryClient

# import chevron
from pulumi import Input, ResourceOptions
from pulumi.dynamic import (
    Resource,
    ResourceProvider,
    CreateResult,
    DiffResult,
    UpdateResult,
)

# Local imports
from data_safe_haven.exceptions import DataSafeHavenAzureException


class FileShareFileProps:
    """Props for the FileShareFile class"""

    def __init__(
        self,
        destination_path: Input[str],
        share_name: Input[str],
        file_contents: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
    ):
        self.destination_path = destination_path
        self.share_name = share_name
        self.file_contents = file_contents
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name


class _FileShareFileProps:
    """Unwrapped version of FileShareFileProps"""

    def __init__(
        self,
        destination_path: str,
        share_name: str,
        file_contents: str,
        storage_account_key: str,
        storage_account_name: str,
    ):
        self.destination_path = destination_path
        self.share_name = share_name
        self.file_contents = file_contents
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name


class FileShareFileProvider(ResourceProvider):
    def create(self, props: _FileShareFileProps) -> CreateResult:
        """Upload file contents to the target storage account location."""
        try:
            tokens = props["destination_path"].split("/")
            directory = "/".join(tokens[:-1])
            target = tokens[-1]
            file_client = self.get_file_client(
                props["storage_account_name"],
                props["storage_account_key"],
                props["share_name"],
                target,
                directory=directory,
            )
            file_client.upload_file(props["file_contents"].encode("utf-8"))
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to upload data to <fg=green>{target}</> in <fg=green>{props['share_name']}</>."
            ) from exc
        return CreateResult(
            f"filesharefile-{binascii.b2a_hex(os.urandom(16)).decode('utf-8')}",
            outs={**props},
        )

    def delete(self, id: str, props: _FileShareFileProps):
        """Delete a file from the target storage account"""
        try:
            tokens = props["destination_path"].split("/")
            directory = "/".join(tokens[:-1])
            target = tokens[-1]
            file_client = self.get_file_client(
                props["storage_account_name"],
                props["storage_account_key"],
                props["share_name"],
                target,
                directory=directory,
            )
            if self.file_exists(file_client):
                file_client.delete_file()
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to delete file <fg=green>{target}</> in <fg=green>{props['share_name']}</>."
            ) from exc

    def diff(
        self,
        id: str,
        oldProps: _FileShareFileProps,
        newProps: _FileShareFileProps,
    ) -> DiffResult:
        """Calculate diff between old and new state"""
        replaces = []
        # If any of the following are changed then the resource must be replaced
        for property in [
            "destination_path",
            "share_name",
            "file_contents",
            "storage_account_name",
        ]:
            if (property not in oldProps) or (oldProps[property] != newProps[property]):
                replaces.append(property)
        return DiffResult(
            changes=(oldProps != newProps),  # changes are needed
            replaces=replaces,  # replacement is needed
            stables=None,  # list of inputs that are constant
            delete_before_replace=True,  # delete the existing resource before replacing
        )

    @staticmethod
    def file_exists(file_client):
        try:
            file_client.get_file_properties()
            return True
        except ResourceNotFoundError:
            return False

    @staticmethod
    def get_file_client(
        storage_account_name,
        storage_account_key,
        share_name,
        file_name,
        directory=None,
    ):
        if directory:
            directory_client = ShareDirectoryClient(
                account_url=f"https://{storage_account_name}.file.core.windows.net",
                share_name=share_name,
                directory_path=directory,
                credential=storage_account_key,
            )
            if not directory_client.exists():
                directory_client.create_directory()
            return directory_client.get_file_client(file_name)
        return ShareFileClient(
            account_url=f"https://{storage_account_name}.file.core.windows.net",
            share_name=share_name,
            file_path=file_name,
            credential=storage_account_key,
        )

    def update(
        self,
        id: str,
        oldProps: _FileShareFileProps,
        newProps: _FileShareFileProps,
    ) -> DiffResult:
        """Updating is identical to creating."""
        updated = self.create(newProps)
        return UpdateResult(outs={**updated.outs})


class FileShareFile(Resource):
    def __init__(
        self,
        name: str,
        props: FileShareFileProps,
        opts: Optional[ResourceOptions] = None,
    ):
        self._resource_type_name = "storage:FileShareFile"  # set resource type
        super().__init__(FileShareFileProvider(), name, {**vars(props)}, opts)
