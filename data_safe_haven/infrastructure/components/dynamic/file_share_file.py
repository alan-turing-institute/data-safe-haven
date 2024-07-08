"""Pulumi dynamic component for files uploaded to an Azure FileShare."""

from contextlib import suppress
from typing import Any

from azure.core.exceptions import ResourceNotFoundError, ServiceRequestError
from azure.storage.fileshare import ShareDirectoryClient, ShareFileClient
from pulumi import Input, Output, ResourceOptions
from pulumi.dynamic import CreateResult, DiffResult, Resource

from data_safe_haven.exceptions import DataSafeHavenAzureError

from .dsh_resource_provider import DshResourceProvider


class FileShareFileProps:
    """Props for the FileShareFile class"""

    def __init__(
        self,
        destination_path: Input[str],
        file_contents: Input[str],
        share_name: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
    ) -> None:
        self.destination_path = destination_path
        self.file_contents = file_contents
        self.share_name = share_name
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name


class FileShareFileProvider(DshResourceProvider):
    @staticmethod
    def file_exists(file_client: ShareFileClient) -> bool:
        with suppress(ResourceNotFoundError, ServiceRequestError):
            file_client.get_file_properties()
            return True
        return False

    @staticmethod
    def get_file_client(
        storage_account_name: str,
        storage_account_key: str,
        share_name: str,
        destination_path: str,
    ) -> ShareFileClient:
        tokens = destination_path.split("/")
        directory = "/".join(tokens[:-1])
        file_name = tokens[-1]
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

    def create(self, props: dict[str, Any]) -> CreateResult:
        """Create file in target storage account with specified contents."""
        outs = dict(**props)
        file_client: ShareFileClient | None = None
        try:
            file_client = self.get_file_client(
                props["storage_account_name"],
                props["storage_account_key"],
                props["share_name"],
                props["destination_path"],
            )
            file_client.upload_file(props["file_contents"].encode("utf-8"))
            outs["file_name"] = file_client.file_name
        except Exception as exc:
            file_name = file_client.file_name if file_client else ""
            msg = f"Failed to upload data to '{file_name}' in [green]{props['share_name']}[/]."
            raise DataSafeHavenAzureError(msg) from exc
        return CreateResult(
            f"filesharefile-{props['destination_path'].replace('/', '-')}",
            outs=outs,
        )

    def delete(self, id_: str, props: dict[str, Any]) -> None:
        """Delete a file from the target storage account"""
        # Use `id` as a no-op to avoid ARG002 while maintaining function signature
        id(id_)
        file_client: ShareFileClient | None = None
        try:
            file_client = self.get_file_client(
                props["storage_account_name"],
                props["storage_account_key"],
                props["share_name"],
                props["destination_path"],
            )
            if self.file_exists(file_client):
                file_client.close_all_handles()
                file_client.delete_file()
        except Exception as exc:
            file_name = file_client.file_name if file_client else ""
            msg = f"Failed to delete file '{file_name}' in [green]{props['share_name']}[/]."
            raise DataSafeHavenAzureError(msg) from exc

    def diff(
        self,
        id_: str,
        old_props: dict[str, Any],
        new_props: dict[str, Any],
    ) -> DiffResult:
        """Calculate diff between old and new state"""
        # Use `id` as a no-op to avoid ARG002 while maintaining function signature
        id(id_)
        # Exclude "storage_account_key" which should not trigger a diff
        return self.partial_diff(old_props, new_props, ["storage_account_key"])

    def refresh(self, props: dict[str, Any]) -> dict[str, Any]:
        with suppress(Exception):
            file_client = FileShareFileProvider.get_file_client(
                props["storage_account_name"],
                props["storage_account_key"],
                props["share_name"],
                props["destination_path"],
            )
            if not FileShareFileProvider.file_exists(file_client):
                props["file_name"] = ""
        return dict(**props)


class FileShareFile(Resource):
    file_name: Output[str]
    _resource_type_name = "dsh:common:FileShareFile"  # set resource type

    def __init__(
        self,
        name: str,
        props: FileShareFileProps,
        opts: ResourceOptions | None = None,
    ):
        super().__init__(
            FileShareFileProvider(), name, {"file_name": None, **vars(props)}, opts
        )
