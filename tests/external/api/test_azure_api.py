import pytest
from pytest import fixture

import data_safe_haven.external.api.azure_api
from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.external.api.azure_api import AzureApi


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
                raise Exception

    monkeypatch.setattr(
        data_safe_haven.external.api.azure_api, "KeyClient", MockKeyClient
    )


@fixture
def mock_blob_client(monkeypatch):  # noqa: ARG001
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


class TestAzureApi:
    def test_get_keyvault_key(self, mock_key_client):  # noqa: ARG002
        api = AzureApi("subscription name")
        key = api.get_keyvault_key("exists", "key vault name")
        assert key == "key: exists"

    def test_get_keyvault_key_missing(self, mock_key_client):  # noqa: ARG002
        api = AzureApi("subscription name")
        with pytest.raises(
            DataSafeHavenAzureError, match="Failed to retrieve key does not exist"
        ):
            api.get_keyvault_key("does not exist", "key vault name")

    def test_blob_exists(self, mock_blob_client):  # noqa: ARG002
        api = AzureApi("subscription name")
        assert api.blob_exists(
            "resource_group", "storage_account", "storage_container", "exists"
        )

    def test_blob_does_not_exist(self, mock_blob_client):  # noqa: ARG002
        api = AzureApi("subscription name")
        assert not api.blob_exists(
            "resource_group", "storage_account", "storage_container", "abc.txt"
        )
