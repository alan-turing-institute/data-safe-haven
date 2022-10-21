"""Configuration file backed by blob storage"""
# Standard library imports
import re
from typing import Any, Optional

import dotmap
import yaml
from azure.core.exceptions import ResourceNotFoundError
from azure.mgmt.storage import StorageManagementClient

# Third party imports
from azure.storage.blob import BlobServiceClient

# Local imports
from data_safe_haven import __version__
from data_safe_haven.exceptions import DataSafeHavenAzureException
from data_safe_haven.mixins import AzureMixin, LoggingMixin


class Config(LoggingMixin, AzureMixin):
    """Configuration file backed by blob storage"""

    def __init__(
        self,
        name: str,
        subscription_name: str,
        *args: Optional[Any],
        **kwargs: Optional[Any],
    ):
        # Load the Azure mixin
        super().__init__(*args, subscription_name=subscription_name, **kwargs)

        # Set names
        self.name = name
        self.shm_name = re.sub(r"[^0-9a-zA-Z]+", "", self.name).lower()

        # Construct backend storage variables
        backend_resource_group_name = f"rg-shm-{self.shm_name}-backend"
        backend_storage_account_name = (
            f"shm{self.shm_name[:12]}backend"  # maximum of 24 characters allowed
        )
        backend_storage_container_name = "config"

        # Try to load the full config from blob storage
        try:
            self._map = self.download(
                backend_resource_group_name,
                backend_storage_account_name,
                backend_storage_container_name,
            )
        # ... otherwise create a new DotMap
        except (DataSafeHavenAzureException, ResourceNotFoundError):
            self._map = dotmap.DotMap()

        # Update the map with local config variables
        # Set defaults by checking whether the variable has been set or defaults to a DotMap
        if isinstance(self.tags.deployed_by, dotmap.DotMap):
            self.tags.deployed_by = "Python"
        if isinstance(self.tags.deployment, dotmap.DotMap):
            self.tags.deployment = self.name
        if isinstance(self.tags.project, dotmap.DotMap):
            self.tags.project = "Data Safe Haven"
        if isinstance(self.tags.version, dotmap.DotMap):
            self.tags.version = __version__
        if isinstance(self.backend.key_vault_name, dotmap.DotMap):
            self.backend.key_vault_name = f"kv-{self.shm_name[:13]}-backend"
        if isinstance(self.backend.resource_group_name, dotmap.DotMap):
            self.backend.resource_group_name = backend_resource_group_name
        if isinstance(self.backend.storage_account_name, dotmap.DotMap):
            self.backend.storage_account_name = backend_storage_account_name
        if isinstance(self.backend.storage_container_name, dotmap.DotMap):
            self.backend.storage_container_name = backend_storage_container_name
        if isinstance(self.backend.managed_identity_name, dotmap.DotMap):
            self.backend.managed_identity_name = "KeyVaultReaderIdentity"
        if isinstance(self.backend.pulumi_encryption_key_name, dotmap.DotMap):
            self.backend.pulumi_encryption_key_name = "pulumi-encryption-key"
        if isinstance(self.pulumi.storage_container_name, dotmap.DotMap):
            self.pulumi.storage_container_name = "pulumi"
        if isinstance(self.shm.name, dotmap.DotMap):
            self.shm.name = self.shm_name

    def __repr__(self) -> str:
        return f"{self.__class__} containing: {self._map}"

    def __str__(self) -> str:
        return yaml.dump(self._map.toDict(), indent=2)

    def __getattr__(self, name):
        """Access unknown attributes from the internal map"""
        return self._map[name]

    @property
    def filename(self) -> str:
        """Filename where this configuration will be stored"""
        return f"config-{self.shm_name}.yaml"

    def download(
        self,
        backend_resource_group_name: str,
        backend_storage_account_name: str,
        backend_storage_container_name: str,
    ) -> dotmap.DotMap:
        """Load the config file from Azure storage"""
        try:
            # Connect to blob storage
            storage_account_key = self.storage_account_key(
                backend_resource_group_name, backend_storage_account_name
            )
            blob_service_client = BlobServiceClient.from_connection_string(
                f"DefaultEndpointsProtocol=https;AccountName={backend_storage_account_name};AccountKey={storage_account_key};EndpointSuffix=core.windows.net"
            )
            # Download the created file
            blob_client = blob_service_client.get_blob_client(
                container=backend_storage_container_name, blob=self.filename
            )
            return dotmap.DotMap(yaml.safe_load(blob_client.download_blob().readall()))
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Configuration file could not be downloaded from '{backend_storage_account_name}'\n{str(exc)}."
            ) from exc

    def storage_account_key(
        self, backend_resource_group_name: str, backend_storage_account_name: str
    ) -> str:
        """Load the key for the backend storage account"""
        try:
            storage_client = StorageManagementClient(
                self.credential, self.subscription_id
            )
            storage_keys = storage_client.storage_accounts.list_keys(
                backend_resource_group_name,
                backend_storage_account_name,
            )
            return storage_keys.keys[0].value
        except Exception as exc:
            raise DataSafeHavenAzureException(
                "Storage key could not be loaded."
            ) from exc

    def upload(self) -> None:
        """Dump the config file to Azure storage"""
        self.info(
            f"Uploading config <fg=green>{self.name}</> to blob storage.",
            no_newline=True,
        )
        try:
            # Connect to blob storage
            storage_account_key = self.storage_account_key(
                self.backend.resource_group_name, self.backend.storage_account_name
            )
            blob_service_client = BlobServiceClient.from_connection_string(
                f"DefaultEndpointsProtocol=https;AccountName={self.backend.storage_account_name};AccountKey={storage_account_key};EndpointSuffix=core.windows.net"
            )
            # Upload the created file
            blob_client = blob_service_client.get_blob_client(
                container=self.backend.storage_container_name, blob=self.filename
            )
            blob_client.upload_blob(str(self), overwrite=True)
            self.info(
                f"Uploaded config <fg=green>{self.name}</> to blob storage.",
                overwrite=True,
            )
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Configuration file could not be uploaded to '{self.backend.storage_account_name}'."
            ) from exc
