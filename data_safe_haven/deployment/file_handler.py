"""Deploy with Pulumi"""
# Standard library imports
import pathlib

# Third party imports
from azure.storage.fileshare import ShareFileClient, ShareDirectoryClient
import chevron

# Local imports
from data_safe_haven.exceptions import DataSafeHavenAzureException
from data_safe_haven.mixins import LoggingMixin


class FileHandler(LoggingMixin):
    """Upload local files to Azure, handling template expansion"""

    def __init__(self, storage_account_name, storage_account_key, *args, **kwargs):
        self.sa_name = storage_account_name
        self.sa_key = storage_account_key
        super().__init__(*args, **kwargs)

    def get_file_client(self, share_name, destination_path, directory=None):
        if directory:
            directory_client = ShareDirectoryClient(
                account_url=f"https://{self.sa_name}.file.core.windows.net",
                share_name=share_name,
                directory_path=directory,
                credential=self.sa_key,
            )
            if not directory_client.exists():
                directory_client.create_directory()
            return directory_client.get_file_client(destination_path)
        return ShareFileClient(
            account_url=f"https://{self.sa_name}.file.core.windows.net",
            share_name=share_name,
            file_path=destination_path,
            credential=self.sa_key,
        )

    def get_file_contents(self, file_path, mustache_values=None):
        """Read a local file into a bytearray for upload, expanding template values"""
        self.info(f"Reading file contents from <fg=green>{file_path}</>...")
        with open(file_path, "r") as source_file:
            if mustache_values:
                contents = chevron.render(source_file, mustache_values).encode("utf-8")
            else:
                contents = source_file.read().encode("utf-8")
        return contents

    def upload(
        self,
        share_name,
        source_path,
        directory=None,
        destination_path=None,
        mustache_values=None,
    ):
        """Upload a file to the fileshare"""
        try:
            source_path = pathlib.Path(source_path)
            if not destination_path:
                destination_path = source_path.parts[-1].replace(".mustache", "")
            self.info(
                f"Uploading file as <fg=green>{destination_path}</> in <fg=green>{share_name}</>..."
            )
            file_client = self.get_file_client(share_name, destination_path, directory)
            file_contents = self.get_file_contents(source_path, mustache_values)
            file_client.upload_file(file_contents)
            self.info(
                f"Uploaded file as <fg=green>{destination_path}</> in <fg=green>{share_name}</>."
            )
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to upload file as <fg=green>{destination_path}</> in <fg=green>{share_name}</>."
            ) from exc
