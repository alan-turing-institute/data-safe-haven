"""Command-line application for initialising a Data Safe Haven deployment"""
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.exceptions import (
    DataSafeHavenCloudException,
    DataSafeHavenInputException,
)
from azure.core.exceptions import (
    ClientAuthenticationError,
    HttpResponseError,
    ResourceNotFoundError,
)
from azure.identity import DefaultAzureCredential
from azure.keyvault.keys import KeyClient
from azure.mgmt.resource import ResourceManagementClient, SubscriptionClient
from azure.mgmt.keyvault import KeyVaultManagementClient
from azure.mgmt.storage import StorageManagementClient


class Backend(LoggingMixin):
    """Ensure that pulumi backend exists"""

    def __init__(self, config):
        self.cfg = config
        self.tags = {"component": "pulumi"} | self.cfg.tags
        self.credential_ = None
        self.subscription_id_ = None
        self.tenant_id_ = None
        super().__init__()

    def create(self):
        self.ensure_resource_group()
        self.ensure_storage_account()
        self.ensure_storage_container()
        self.ensure_key_vault()
        self.ensure_encryption_key()

    @property
    def credential(self):
        if not self.credential_:
            self.credential_ = DefaultAzureCredential()
        return self.credential_

    @property
    def subscription_id(self):
        if not self.subscription_id_:
            self.azure_login()
        return self.subscription_id_

    @property
    def tenant_id(self):
        if not self.tenant_id_:
            self.azure_login()
        return self.tenant_id_

    def azure_login(self):
        """Get subscription and tenant IDs"""
        # Connect to Azure clients
        subscription_client = SubscriptionClient(self.credential)

        # Check that the Azure credentials are valid
        try:
            for subscription in subscription_client.subscriptions.list():
                self.debug(
                    f"Found subscription {subscription.display_name} ({subscription.id})"
                )
                if subscription.display_name == self.cfg.azure.subscription_name:
                    self.info(
                        f"Will use subscription <fg=green>{subscription.display_name}</> ({subscription.id})"
                    )
                    self.subscription_id_ = subscription.subscription_id
                    self.tenant_id_ = subscription.tenant_id
                    break
            self.info(
                f"Successfully authenticated using: {self.credential.__class__.__name__}"
            )
        except ClientAuthenticationError as exc:
            raise DataSafeHavenCloudException(
                "Failed to authenticate with Azure"
            ) from exc
        if not (self.subscription_id and self.tenant_id):
            raise DataSafeHavenInputException(
                f"Could not find subscription '{self.cfg.azure.subscription_name}'"
            )

    def ensure_resource_group(self):
        """Ensure that backend resource group exists"""
        # Connect to Azure clients
        resource_client = ResourceManagementClient(
            self.credential, self.subscription_id
        )

        # Ensure that resource group exists
        self.info(
            f"Ensuring that resource group {self.cfg.pulumi.resource_group_name} exists..."
        )
        resource_client.resource_groups.create_or_update(
            self.cfg.pulumi.resource_group_name,
            {"location": self.cfg.azure.location, "tags": self.tags},
        )
        resource_groups = [
            rg
            for rg in resource_client.resource_groups.list()
            if rg.name == self.cfg.pulumi.resource_group_name
        ]
        if resource_groups:
            self.info(
                f"Found resource group {resource_groups[0].name} in {resource_groups[0].location}"
            )
        else:
            raise DataSafeHavenCloudException(
                f"Failed to create resource group {self.cfg.pulumi.resource_group_name}"
            )

    def ensure_storage_account(self):
        """Ensure that backend storage account exists"""
        # Connect to Azure clients
        storage_client = StorageManagementClient(self.credential, self.subscription_id)

        self.info(
            f"Ensuring that storage account {self.cfg.pulumi.storage_account_name} exists..."
        )
        try:
            poller = storage_client.storage_accounts.begin_create(
                self.cfg.pulumi.resource_group_name,
                self.cfg.pulumi.storage_account_name,
                {
                    "location": self.cfg.azure.location,
                    "kind": "StorageV2",
                    "sku": {"name": "Standard_LRS"},
                    "tags": self.tags,
                },
            )
            storage_account = poller.result()
            self.info(
                f"Found storage account {storage_account.name} in {storage_account.location}"
            )
        except HttpResponseError as exc:
            raise DataSafeHavenCloudException(
                f"Failed to create storage account {self.cfg.pulumi.resource_group_name}!"
            ) from exc

    def ensure_storage_container(self):
        """Ensure that backend storage container exists"""
        # Connect to Azure clients
        storage_client = StorageManagementClient(self.credential, self.subscription_id)

        self.info(
            f"Ensuring that storage container {self.cfg.pulumi.storage_container_name} exists..."
        )
        try:
            container = storage_client.blob_containers.create(
                self.cfg.pulumi.resource_group_name,
                self.cfg.pulumi.storage_account_name,
                self.cfg.pulumi.storage_container_name,
                {"public_access": "none"},
            )
            self.info(f"Found storage container {container.name}")
            # print(str(container))
            # self.container_path = "https://{container.name}.blob.core.windows.net/"
            # print(self.container_path)
        except HttpResponseError as exc:
            raise DataSafeHavenCloudException(
                f"Failed to create storage container {self.cfg.pulumi.storage_container_name}!"
            ) from exc

    def ensure_key_vault(self):
        """Ensure that backend key vault exists"""
        # Connect to Azure clients
        key_vault_client = KeyVaultManagementClient(
            self.credential, self.subscription_id
        )

        # Ensure that key vault exists
        self.info(f"Ensuring that key vault {self.cfg.pulumi.key_vault_name} exists...")
        key_vault_client.vaults.begin_create_or_update(
            self.cfg.pulumi.resource_group_name,
            self.cfg.pulumi.key_vault_name,
            {
                "location": self.cfg.azure.location,
                "tags": self.tags,
                "properties": {
                    "sku": {
                        "name": "standard",
                        "family": "A",
                    },
                    "tenant_id": self.tenant_id,
                    "access_policies": [
                        {
                            "tenant_id": self.tenant_id,
                            "object_id": self.cfg.azure.admin_group_id,
                            "permissions": {
                                "keys": ["GET", "LIST", "CREATE", "DECRYPT", "ENCRYPT"],
                            },
                        }
                    ],
                },
            },
        )
        key_vaults = [
            kv
            for kv in key_vault_client.vaults.list()
            if kv.name == self.cfg.pulumi.key_vault_name
        ]
        if key_vaults:
            self.info(
                f"Found key vault {key_vaults[0].name} in {key_vaults[0].location}"
            )
        else:
            raise DataSafeHavenCloudException(
                f"Failed to create key vault {self.cfg.pulumi.key_vault_name}"
            )

    def ensure_encryption_key(self):
        """Ensure that backend encryption key exists"""
        # Connect to Azure clients
        key_client = KeyClient(
            f"https://{self.cfg.pulumi.key_vault_name}.vault.azure.net", self.credential
        )

        # Ensure that key exists
        self.info(f"Ensuring that key {self.cfg.pulumi.encryption_key_name} exists...")
        key = None
        try:
            key = key_client.get_key(self.cfg.pulumi.encryption_key_name)
        except (HttpResponseError, ResourceNotFoundError):
            key_client.create_rsa_key(self.cfg.pulumi.encryption_key_name, size=2048)
        try:
            if not key:
                key = key_client.get_key(self.cfg.pulumi.encryption_key_name)
            self.info(f"Found key {key.name}")
        except (HttpResponseError, ResourceNotFoundError):
            raise DataSafeHavenCloudException(
                f"Failed to create resource group {self.cfg.pulumi.key_vault_name}"
            )

    def storage_credentials(self):
        # Connect to Azure clients
        storage_client = StorageManagementClient(self.credential, self.subscription_id)
        key_client = KeyClient(
            f"https://{self.cfg.pulumi.key_vault_name}.vault.azure.net", self.credential
        )

        # Load account details
        storage_accounts = [
            sa
            for sa in storage_client.storage_accounts.list()
            if sa.name == self.cfg.pulumi.storage_account_name
        ]
        storage_keys = storage_client.storage_accounts.list_keys(
            self.cfg.pulumi.resource_group_name, self.cfg.pulumi.storage_account_name
        )
        key = key_client.get_key(self.cfg.pulumi.encryption_key_name)

        try:
            return {
                "AZURE_STORAGE_ACCOUNT": storage_accounts[0].name,
                "AZURE_STORAGE_KEY": storage_keys.keys[0].value,
                "AZURE_KEY_ID": key.id,
            }
        except Exception as exc:
            raise DataSafeHavenCloudException(
                f"Failed to load storage account credentials"
            ) from exc
