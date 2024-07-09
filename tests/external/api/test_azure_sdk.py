import pytest
from azure.core.exceptions import ResourceNotFoundError
from pytest import fixture

import data_safe_haven.external.api.azure_sdk
from data_safe_haven.exceptions import DataSafeHavenAzureError
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


class TestAzureSdk:
    def test_entra_directory(self):
        api = AzureSdk("subscription name")
        assert isinstance(api.entra_directory, GraphApi)

    def test_subscription_id(
        self,
        mock_azureapi_get_subscription,  # noqa: ARG002
    ):
        api = AzureSdk("subscription name")
        assert api.subscription_id == pytest.guid_subscription

    def test_tenant_id(
        self,
        mock_azureapi_get_subscription,  # noqa: ARG002
    ):
        api = AzureSdk("subscription name")
        assert api.tenant_id == pytest.guid_tenant

    def test_blob_exists(self, mock_blob_client):  # noqa: ARG002
        api = AzureSdk("subscription name")
        exists = api.blob_exists(
            "exists", "resource_group", "storage_account", "storage_container"
        )
        assert isinstance(exists, bool)
        assert exists

    def test_blob_does_not_exist(self, mock_blob_client):  # noqa: ARG002
        api = AzureSdk("subscription name")
        exists = api.blob_exists(
            "abc.txt", "resource_group", "storage_account", "storage_container"
        )
        assert isinstance(exists, bool)
        assert not exists

    def test_get_keyvault_key(self, mock_key_client):  # noqa: ARG002
        api = AzureSdk("subscription name")
        key = api.get_keyvault_key("exists", "key vault name")
        assert key == "key: exists"

    def test_get_keyvault_key_missing(self, mock_key_client):  # noqa: ARG002
        api = AzureSdk("subscription name")
        with pytest.raises(
            DataSafeHavenAzureError, match="Failed to retrieve key does not exist"
        ):
            api.get_keyvault_key("does not exist", "key vault name")
