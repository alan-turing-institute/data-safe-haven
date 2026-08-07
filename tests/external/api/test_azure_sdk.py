import pytest
from azure.core.exceptions import ClientAuthenticationError, ResourceNotFoundError
from azure.mgmt.keyvault.models import DeletedVault
from azure.mgmt.storage.models import StorageAccountListKeysResult
from azure.mgmt.subscription import SubscriptionClient
from azure.mgmt.subscription.models import Subscription
from pytest import CaptureFixture, fixture

import data_safe_haven.external.api.azure_sdk
from data_safe_haven.exceptions import (
    DataSafeHavenAzureAPIAuthenticationError,
    DataSafeHavenAzureError,
    DataSafeHavenAzureStorageError,
    DataSafeHavenValueError,
)
from data_safe_haven.external import AzureSdk, GraphApi
from data_safe_haven.infrastructure import SREProjectManager


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
        data_safe_haven.external.api.azure_sdk.AzureSdk,
        "blob_client_",
        mock_blob_client,
    )


@fixture
def mock_share_client(monkeypatch):
    class MockShareFileClient:
        def __init__(self, file_name):
            self.file_name = file_name

        def exists(self):
            if self.file_name == "exists":
                return True
            else:
                return False

    class MockShareClient:
        def __init__(
            self,
            resource_group_name,
            storage_account_name,
            file_share_name,
        ):
            self.resource_group_name = resource_group_name
            self.storage_account_name = storage_account_name
            self.file_share_name = file_share_name

        def get_file_client(self, file_name):
            return MockShareFileClient(
                file_name,
            )

    def mock_share_client(
        self,  # noqa: ARG001
        resource_group_name,
        storage_account_name,
        file_share_name,
    ):
        return MockShareClient(
            resource_group_name,
            storage_account_name,
            file_share_name,
        )

    monkeypatch.setattr(
        data_safe_haven.external.api.azure_sdk.AzureSdk,
        "share_client_",
        mock_share_client,
    )


@fixture
def mock_share_service_client(monkeypatch):
    class MockShareServiceClient:
        def __init__(self, resource_group_name, storage_account_name):
            self.resource_group_name = resource_group_name
            self.storage_account_name = storage_account_name

        def list_shares(self):
            return ["file_share_name", "file_share_name2"]

    monkeypatch.setattr(
        data_safe_haven.external.api.azure_sdk.AzureSdk,
        "share_service_client_",
        MockShareServiceClient,
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
        mock_azuresdk_get_credential,  # noqa: ARG002
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
            match=r"Storage account 'storage_account' could not be found.",
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

    def test_file_share_exists(
        self, mock_share_client, mock_storage_exists  # noqa: ARG002
    ):
        sdk = AzureSdk("subscription name")
        exists = sdk.file_share_exists(
            "exists", "resource_group", "storage_account", "file_share_name"
        )
        assert isinstance(exists, bool)
        assert exists

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
            match=r"Failed to authenticate with Azure API.",
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
        result = sdk.purge_keyvault("key_vault_name", "location")
        stdout, _ = capsys.readouterr()
        assert "Found deleted key vault key_vault_name in location" in stdout
        assert "Purging deleted key vault key_vault_name in location" in stdout
        assert result is True

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

    def test_get_resource(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        mock_azuresdk_resource_manager_client: None,  # noqa: ARG002
    ) -> None:
        """Check that the AzureSdk code for getting a resource is acting
        sensibly.
        """
        subscription_id = "35ebced1-4e7a-4c1f-b634-c0886937085d"
        resource_group = sre_project_manager.output("sre_resource_group")
        provider_namespace = "Provider"
        resource_type = "ResourceType"
        resource_name = "ResourceName"
        resource_id = f"/subscriptions/{subscription_id}/resourceGroups/{resource_group}/providers/{provider_namespace}/{resource_type}/{resource_name}"
        azure_sdk = AzureSdk(sre_project_manager.context.subscription_name)
        resource = azure_sdk.get_resource(
            resource_group, provider_namespace, resource_type, resource_name
        )
        assert resource.id == resource_id

    def test_get_endpoint(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        mock_azuresdk_resource_manager_client: None,  # noqa: ARG002
    ) -> None:
        """Check that the AzureSdk code for getting a private endpoint is acting
        sensibly.
        """
        subscription_id = "35ebced1-4e7a-4c1f-b634-c0886937085d"
        resource_group = sre_project_manager.output("sre_resource_group")
        provider_namespace = "Microsoft.Network"
        resource_type = "privateEndpoints"
        resource_name = "endpoint"
        resource_id = f"/subscriptions/{subscription_id}/resourceGroups/{resource_group}/providers/{provider_namespace}/{resource_type}/{resource_name}"
        azure_sdk = AzureSdk(sre_project_manager.context.subscription_name)
        resource = azure_sdk.get_private_endpoint(resource_group, resource_name)
        assert resource.id == resource_id

    def test_get_subnet(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        mock_azuresdk_resource_manager_client: None,  # noqa: ARG002
    ) -> None:
        """Check that the AzureSdk code for getting a subnet is acting sensibly."""
        subscription_id = "35ebced1-4e7a-4c1f-b634-c0886937085d"
        resource_group = sre_project_manager.output("sre_resource_group")
        provider_namespace = "Microsoft.Network"
        resource_type = "virtualNetworks"
        vnet_name = "vnet"
        resource_name = "subnet"
        resource_id = f"/subscriptions/{subscription_id}/resourceGroups/{resource_group}/providers/{provider_namespace}/{resource_type}/{vnet_name}/subnets/{resource_name}"
        azure_sdk = AzureSdk(sre_project_manager.context.subscription_name)
        resource = azure_sdk.get_subnet(resource_group, vnet_name, resource_name)
        assert resource.id == resource_id

    def test_delete_resources(
        self,
        sre_project_manager: SREProjectManager,
        capsys: CaptureFixture[str],
        mock_azuresdk_resource_manager_client: None,  # noqa: ARG002
    ) -> None:
        """Check that the AzureSdk code for deleting a set of resources is
        acting sensibly.
        """
        azure_sdk = AzureSdk(sre_project_manager.context.subscription_name)
        azure_sdk.delete_resources(["first", "second", "third", "fourth", "fifth"])
        captured = capsys.readouterr()
        assert "Deleting 5 resources" in captured.out
        assert "Operations remaining: 5" in captured.out
        assert "Operations remaining: 4" in captured.out
        assert "Operations remaining: 3" in captured.out
        assert "Operations remaining: 2" in captured.out
        assert "Operations remaining: 1" in captured.out
        assert "Operations remaining: 6" not in captured.out
        assert "All deletion operations completed" in captured.out
