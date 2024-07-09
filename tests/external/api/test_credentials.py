import pytest
from azure.identity import AzureCliCredential

from data_safe_haven.external.api.credentials import AzureSdkCredential


class TestAzureSdkCredential:
    def test_get_credential(self, mock_azureclicredential_get_token):  # noqa: ARG002
        credential = AzureSdkCredential()
        assert isinstance(credential.get_credential(), AzureCliCredential)

    def test_get_token(self, mock_azureclicredential_get_token):  # noqa: ARG002
        credential = AzureSdkCredential()
        assert isinstance(credential.token, str)

    def test_decode_token(self, mock_azureclicredential_get_token):  # noqa: ARG002
        token = AzureSdkCredential().token
        decoded = AzureSdkCredential.decode_token(token)
        assert decoded["name"] == "username"
        assert decoded["oid"] == pytest.user_id
        assert decoded["upn"] == "username@example.com"
        assert decoded["tid"] == pytest.guid_tenant
