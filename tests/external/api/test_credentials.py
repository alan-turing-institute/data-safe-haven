import pytest
from azure.identity import AzureCliCredential, DeviceCodeCredential

from data_safe_haven.external.api.credentials import (
    AzureSdkCredential,
    GraphApiCredential,
)


class TestAzureSdkCredential:
    def test_get_credential(self, mock_azureclicredential_get_token):  # noqa: ARG002
        credential = AzureSdkCredential()
        assert isinstance(credential.get_credential(), AzureCliCredential)

    def test_get_token(self, mock_azureclicredential_get_token):  # noqa: ARG002
        credential = AzureSdkCredential()
        assert isinstance(credential.token, str)

    def test_decode_token(self, mock_azureclicredential_get_token):  # noqa: ARG002
        credential = AzureSdkCredential()
        decoded = credential.decode_token(credential.token)
        assert decoded["name"] == "username"
        assert decoded["oid"] == pytest.user_id
        assert decoded["upn"] == "username@example.com"
        assert decoded["tid"] == pytest.guid_tenant


class TestGraphApiCredential:
    def test_get_credential(
        self,
        mock_devicecodecredential_get_token,  # noqa: ARG002
        mock_devicecodecredential_authenticate,  # noqa: ARG002
        tmp_config_dir,  # noqa: ARG002
    ):
        credential = GraphApiCredential(pytest.guid_tenant)
        assert isinstance(credential.get_credential(), DeviceCodeCredential)

    def test_get_token(
        self,
        mock_graphapicredential_get_token,  # noqa: ARG002
    ):
        credential = GraphApiCredential(pytest.guid_tenant)
        assert isinstance(credential.token, str)

    def test_decode_token(
        self,
        mock_graphapicredential_get_token,  # noqa: ARG002
    ):
        credential = GraphApiCredential(pytest.guid_tenant)
        decoded = credential.decode_token(credential.token)
        assert decoded["scp"] == "GroupMember.Read.All User.Read.All"
        assert decoded["tid"] == pytest.guid_tenant
