import pytest
from azure.core.exceptions import ClientAuthenticationError, ResourceNotFoundError
from azure.mgmt.keyvault.v2023_07_01.models import DeletedVault
from azure.mgmt.resource.subscriptions import SubscriptionClient
from azure.mgmt.resource.subscriptions.models import Subscription
from azure.mgmt.storage.v2021_08_01.models import (
    StorageAccountListKeysResult,
)
from pytest import fixture

import data_safe_haven.external.api.azure_sdk
from data_safe_haven.exceptions import (
    DataSafeHavenAzureAPIAuthenticationError,
    DataSafeHavenAzureError,
    DataSafeHavenAzureStorageError,
    DataSafeHavenValueError,
)
from data_safe_haven.external import AzureSdk, GraphApi


@fixture
def mock_blob_client(monkeypatch):
    class MockBlobClient:
        def __init__(
            self,
            resource_group_name,  # noqa: ARG002
            storage_account_name,  # noqa: ARG002
            storage_container_name,  # noqa: ARG002
            blob_name,
        ):
            self.blob_name = blob_name

        def exists(self):
            if self.blob_name == "exists":
                return True
            else:
                return False

    def mock_blob_client(
        self,  # noqa: ARG001
        resource_group_name,
        storage_account_name,
        storage_container_name,
        blob_name,
    ):
        return MockBlobClient(
            resource_group_name,
            storage_account_name,
            storage_container_name,
            blob_name,
        )

    monkeypatch.setattr(
        data_safe_haven.external.api.azure_sdk.AzureSdk, "blob_client", mock_blob_client
    )


@fixture
def mock_key_client(monkeypatch):
    class MockKeyClient:
        def __init__(self, vault_url, credential):
            self.vault_url = vault_url
            self.credential = credential

        def get_key(self, key_name):
            if key_name == "exists":
                return f"key: {key_name}"
            else:
                raise ResourceNotFoundError

    monkeypatch.setattr(
        data_safe_haven.external.api.azure_sdk, "KeyClient", MockKeyClient
    )


@fixture
def mock_key_vault_management_client(monkeypatch):
    class Poller:
        def done(self):
            return True

    class MockVaultsOperations:
        def __init__(self, vault_name, location):
            self._vault_name = vault_name
            self._location = location

        def get_deleted(self, vault_name, location):
            if self._vault_name == vault_name and self._location == location:
                print(  # noqa: T201
                    f"Found deleted key vault {vault_name} in {location}"
                )
                return DeletedVault()
            print("Found no deleted key vaults")  # noqa: T201
            return None

        def begin_purge_deleted(self, vault_name, location):
            if self._vault_name == vault_name and self._location == location:
                print(  # noqa: T201
                    f"Purging deleted key vault {vault_name} in {location}"
                )
                self._vault_name = None
            return Poller()

    class MockKeyVaultManagementClient:
        def __init__(self, *args, **kwargs):  # noqa: ARG002
            self.vaults = MockVaultsOperations("key_vault_name", "location")

    monkeypatch.setattr(
        data_safe_haven.external.api.azure_sdk,
        "KeyVaultManagementClient",
        MockKeyVaultManagementClient,
    )


@fixture
def mock_storage_management_client(monkeypatch):
    class MockStorageAccount:
        def __init__(self, name):
            self.name = name

    class MockStorageAccountsOperations:
        def list(self):
            return [
                MockStorageAccount("shmstorageaccount"),
                MockStorageAccount("shmstorageaccounter"),
                MockStorageAccount("shmstorageaccountest"),
            ]

        def list_keys(
            self, resource_group_name, account_name, **kwargs  # noqa: ARG002
        ):
            if account_name == "shmstorageaccount":
                return StorageAccountListKeysResult()
            else:
                return None

    class MockStorageManagementClient:
        def __init__(self, *args, **kwargs):  # noqa: ARG002
            self.storage_accounts = MockStorageAccountsOperations()

    monkeypatch.setattr(
        data_safe_haven.external.api.azure_sdk,
        "StorageManagementClient",
        MockStorageManagementClient,
    )


@fixture
def mock_subscription_client(monkeypatch, request):
    class MockSubscriptionsOperations:
        def __init__(self, *args, **kwargs):
            pass

        def list(self):
            subscription_1 = Subscription()
            subscription_1.display_name = "Subscription 1"
            subscription_1.id = request.config.guid_subscription
            subscription_2 = Subscription()
            subscription_2.display_name = "Subscription 2"
            return [subscription_1, subscription_2]

    class MockSubscriptionClient:
        def __init__(self, *args, **kwargs):
            pass

        @property
        def subscriptions(self):
            return MockSubscriptionsOperations()

    monkeypatch.setattr(
        data_safe_haven.external.api.azure_sdk,
        "SubscriptionClient",
        MockSubscriptionClient,
    )


class TestAzureSdk:
    def test_entra_directory(self):
        sdk = AzureSdk("subscription name")
        assert isinstance(sdk.entra_directory, GraphApi)

    def test_subscription_id(
        self,
        request,
        mock_azuresdk_get_subscription,  # noqa: ARG002
    ):
        sdk = AzureSdk("subscription name")
        assert sdk.subscription_id == request.config.guid_subscription

    def test_tenant_id(
        self,
        request,
        mock_azuresdk_get_subscription,  # noqa: ARG002
    ):
        sdk = AzureSdk("subscription name")
        assert sdk.tenant_id == request.config.guid_tenant

    def test_blob_exists(self, mock_blob_client, mock_storage_exists):  # noqa: ARG002
        sdk = AzureSdk("subscription name")
        exists = sdk.blob_exists(
            "exists", "resource_group", "storage_account", "storage_container"
        )
        assert isinstance(exists, bool)
        assert exists

        mock_storage_exists.assert_called_once_with(
            "storage_account",
        )

    def test_blob_exists_no_storage(
        self,
        mocker,
        mock_blob_client,  # noqa: ARG002
    ):
        sdk = AzureSdk("subscription name")
        mocker.patch.object(sdk, "storage_exists", return_value=False)
        with pytest.raises(
            DataSafeHavenAzureStorageError,
            match="Storage account 'storage_account' could not be found.",
        ):
            sdk.blob_exists(
                "exists", "resource_group", "storage_account", "storage_container"
            )

    def test_blob_does_not_exist(
        self, mock_blob_client, mock_storage_exists  # noqa: ARG002
    ):
        sdk = AzureSdk("subscription name")
        exists = sdk.blob_exists(
            "abc.txt", "resource_group", "storage_account", "storage_container"
        )
        assert isinstance(exists, bool)
        assert not exists

        mock_storage_exists.assert_called_once_with(
            "storage_account",
        )

    def test_get_keyvault_key(self, mock_key_client):  # noqa: ARG002
        sdk = AzureSdk("subscription name")
        key = sdk.get_keyvault_key("exists", "key vault name")
        assert key == "key: exists"

    def test_get_keyvault_key_missing(self, mock_key_client):  # noqa: ARG002
        sdk = AzureSdk("subscription name")
        with pytest.raises(
            DataSafeHavenAzureError, match="Failed to retrieve key does not exist"
        ):
            sdk.get_keyvault_key("does not exist", "key vault name")

    @pytest.mark.parametrize(
        "storage_account_name",
        [("shmstorageaccount"), ("shmstoragenonexistent")],
    )
    def test_get_storage_account_keys(
        self,
        storage_account_name,
        mock_storage_management_client,  # noqa: ARG002
        mock_azuresdk_get_subscription,  # noqa: ARG002
    ):
        sdk = AzureSdk("subscription name")
        if storage_account_name == "shmstorageaccount":
            error_text = "List of keys was empty for storage account 'shmstorageaccount' in resource group 'resource group'."
        else:
            error_text = "No keys were retrieved for storage account 'shmstoragenonexistent' in resource group 'resource group'."

        with pytest.raises(DataSafeHavenAzureStorageError, match=error_text):
            sdk.get_storage_account_keys("resource group", storage_account_name)

    def test_get_subscription(self, request, mock_subscription_client):  # noqa: ARG002
        sdk = AzureSdk("subscription name")
        subscription = sdk.get_subscription("Subscription 1")
        assert isinstance(subscription, Subscription)
        assert subscription.display_name == "Subscription 1"
        assert subscription.id == request.config.guid_subscription

    def test_get_subscription_does_not_exist(
        self, mock_subscription_client  # noqa: ARG002
    ):
        sdk = AzureSdk("subscription name")
        with pytest.raises(
            DataSafeHavenValueError,
            match="Could not find subscription 'Subscription 3'",
        ):
            sdk.get_subscription("Subscription 3")

    def test_get_subscription_authentication_error(self, mocker):
        def raise_client_authentication_error(*args):  # noqa: ARG001
            raise ClientAuthenticationError

        mocker.patch.object(
            SubscriptionClient, "__new__", side_effect=raise_client_authentication_error
        )
        sdk = AzureSdk("subscription name")
        with pytest.raises(
            DataSafeHavenAzureAPIAuthenticationError,
            match="Failed to authenticate with Azure API.",
        ):
            sdk.get_subscription("Subscription 1")

    def test_purge_keyvault(
        self,
        mock_azuresdk_get_subscription,  # noqa: ARG002
        mock_azuresdk_get_credential,  # noqa: ARG002
        mock_key_vault_management_client,  # noqa: ARG002
        capsys,
    ):
        sdk = AzureSdk("subscription name")
        sdk.purge_keyvault("key_vault_name", "location")
        stdout, _ = capsys.readouterr()
        assert "Found deleted key vault key_vault_name in location" in stdout
        assert "Purging deleted key vault key_vault_name in location" in stdout
        assert "Purged Key Vault key_vault_name" in stdout

    @pytest.mark.parametrize(
        "storage_account_name,exists",
        [("shmstorageaccount", True), ("shmstoragenonexistent", False)],
    )
    def test_storage_exists(
        self,
        storage_account_name,
        exists,
        mock_storage_management_client,  # noqa: ARG002
        mock_azuresdk_get_subscription,  # noqa: ARG002
    ):
        sdk = AzureSdk("subscription name")

        assert sdk.storage_exists(storage_account_name) == exists
