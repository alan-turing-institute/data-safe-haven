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


class TestAzureApi:
    def test_get_keyvault_key(self, mock_key_client):  # noqa: ARG002
        api = AzureApi("subscription name")
        key = api.get_keyvault_key("exists", "key vault name")
        assert key == "key: exists"

    def test_get_keyvault_key_missing(self, mock_key_client):  # noqa: ARG002
        api = AzureApi("subscription name")
        with pytest.raises(DataSafeHavenAzureError) as exc:
            api.get_keyvault_key("does not exist", "key vault name")
            assert "Failed to retrieve key does not exist" in exc
