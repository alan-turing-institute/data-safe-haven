import pathlib
import re
import dotmap
import yaml
from data_safe_haven.exceptions import DataSafeHavenAzureException, DataSafeHavenInputException
from data_safe_haven import __version__
from data_safe_haven.mixins.azure_mixin import AzureMixin
from azure.storage.blob import BlobServiceClient
from azure.mgmt.storage import StorageManagementClient
from azure.core.exceptions import ResourceNotFoundError


class Config(AzureMixin):
    alphanumeric = re.compile(r"[^0-9a-zA-Z]+")

    def __init__(self, path, *args, **kwargs):
        try:
            self.read_base_yaml(path)
        except Exception as exc:
            raise DataSafeHavenInputException(
                f"Could not load config YAML file '{path}'"
            ) from exc

        # Load the Azure mixin
        super().__init__(*args, subscription_name=self.data.azure.subscription_name, **kwargs)

        # Try to load the full config from blob storage
        try:
            self.data = self.download()
        # ... otherwise add some basic properties
        except (DataSafeHavenAzureException, ResourceNotFoundError):
            self.add_property("config", {
                "storage_container_name": f"config",
            })
            self.add_property("tags", {
                "deployed_by": "Python",
                "project": "Data Safe Haven",
                "version": __version__,
            })

    def read_base_yaml(self, path):
        with open(pathlib.Path(path), "r") as f_config:
            yaml_ = yaml.safe_load(f_config)
        self.deployment_name = self.alphanumeric.sub("", yaml_["deployment"]["name"]).lower()
        self.data = dotmap.DotMap(yaml_)

    def add_property(self, key, value):
        self.data[key] = value
        self.data = dotmap.DotMap(self.data)

    def __getattr__(self, name):
        return self.data[name]

    def storage_account_key(self):
        try:
            storage_client = StorageManagementClient(self.credential, self.subscription_id)
            storage_keys = storage_client.storage_accounts.list_keys(self.data.metadata.resource_group_name, self.data.metadata.storage_account_name)
            return storage_keys.keys[0].value
        except Exception as exc:
            raise DataSafeHavenAzureException("Storage key could not be loaded.") from exc

    def upload(self):
        """Dump the config file to Azure storage"""
        # Connect to blob storage
        blob_connection_string = f"DefaultEndpointsProtocol=https;AccountName={self.data.metadata.storage_account_name};AccountKey={self.storage_account_key()};EndpointSuffix=core.windows.net"
        blob_service_client = BlobServiceClient.from_connection_string(blob_connection_string)
        # Upload the created file
        blob_client = blob_service_client.get_blob_client(container=self.data.config.storage_container_name, blob=f"config-{self.deployment_name}.yaml")
        blob_client.upload_blob(yaml.dump(self.data.toDict()), overwrite=True)

    def download(self):
        """Load the config file from Azure storage"""
        # Connect to blob storage
        blob_connection_string = f"DefaultEndpointsProtocol=https;AccountName={self.data.metadata.storage_account_name};AccountKey={self.storage_account_key()};EndpointSuffix=core.windows.net"
        blob_service_client = BlobServiceClient.from_connection_string(blob_connection_string)
        # Download the created file
        blob_client = blob_service_client.get_blob_client(container=self.data.config.storage_container_name, blob=f"config-{self.deployment_name}.yaml")
        return dotmap.DotMap(yaml.safe_load(blob_client.download_blob().readall()))
