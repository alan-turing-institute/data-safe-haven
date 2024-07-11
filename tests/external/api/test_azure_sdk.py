import pytest
from azure.core.exceptions import ClientAuthenticationError, ResourceNotFoundError
from azure.mgmt.resource.subscriptions import SubscriptionClient
from azure.mgmt.resource.subscriptions.models import Subscription
from pytest import fixture

import data_safe_haven.external.api.azure_sdk
from data_safe_haven.exceptions import (
    DataSafeHavenAzureAPIAuthenticationError,
    DataSafeHavenAzureError,
    DataSafeHavenValueError,
)
from data_safe_haven.external import AzureSdk, GraphApi


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
def mock_subscription_client(monkeypatch):
    class MockSubscriptionsOperations:
        def __init__(self, *args, **kwargs):
            pass

        def list(self):
            subscription_1 = Subscription()
            subscription_1.display_name = "Subscription 1"
            subscription_1.id = pytest.guid_subscription
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
        mock_azureapi_get_subscription,  # noqa: ARG002
    ):
        sdk = AzureSdk("subscription name")
        assert sdk.subscription_id == pytest.guid_subscription

    def test_tenant_id(
        self,
        mock_azureapi_get_subscription,  # noqa: ARG002
    ):
        sdk = AzureSdk("subscription name")
        assert sdk.tenant_id == pytest.guid_tenant

    def test_blob_exists(self, mock_blob_client):  # noqa: ARG002
        sdk = AzureSdk("subscription name")
        exists = sdk.blob_exists(
            "exists", "resource_group", "storage_account", "storage_container"
        )
        assert isinstance(exists, bool)
        assert exists

    def test_blob_does_not_exist(self, mock_blob_client):  # noqa: ARG002
        sdk = AzureSdk("subscription name")
        exists = sdk.blob_exists(
            "abc.txt", "resource_group", "storage_account", "storage_container"
        )
        assert isinstance(exists, bool)
        assert not exists

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

    def test_get_subscription(self, mock_subscription_client):  # noqa: ARG002
        sdk = AzureSdk("subscription name")
        subscription = sdk.get_subscription("Subscription 1")
        assert isinstance(subscription, Subscription)
        assert subscription.display_name == "Subscription 1"
        assert subscription.id == pytest.guid_subscription

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
