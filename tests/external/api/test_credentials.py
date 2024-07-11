import pytest
from azure.identity import (
    AzureCliCredential,
    DeviceCodeCredential,
)

from data_safe_haven.directories import config_dir
from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.external.api.credentials import (
    AzureSdkCredential,
    GraphApiCredential,
)


class TestDeferredCredential:
    def test_decode_token_error(
        self, mock_azureclicredential_get_token_invalid  # noqa: ARG002
    ):
        credential = AzureSdkCredential()
        with pytest.raises(
            DataSafeHavenAzureError,
            match="Error getting account information from Azure CLI.",
        ):
            credential.decode_token(credential.token)


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

    def test_get_credential_callback(
        self,
        capsys,
        mock_devicecodecredential_new,  # noqa: ARG002
        tmp_config_dir,  # noqa: ARG002
    ):
        credential = GraphApiCredential(pytest.guid_tenant)
        credential.get_credential()
        captured = capsys.readouterr()
        cleaned_stdout = " ".join(captured.out.split())
        assert (
            "Go to VERIFICATION_URI in a web browser and enter the code USER_DEVICE_CODE at the prompt."
            in cleaned_stdout
        )

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

    def test_authentication_record_is_used(
        self,
        mocker,
        authentication_record,
        mock_devicecodecredential_new,
        tmp_config_dir,  # noqa: ARG002
    ):
        credential = GraphApiCredential(pytest.guid_tenant)

        # Write an authentication record
        cache_name = f"dsh-{credential.tenant_id}"
        authentication_record_path = (
            config_dir() / f".msal-authentication-cache-{cache_name}"
        )
        with open(authentication_record_path, "w") as f_auth:
            f_auth.write(authentication_record.serialize())

        credential.get_credential()

        # Note that we cannot check the calls exactly as the objects we use would have
        # different IDs
        mock_devicecodecredential_new.assert_called_once_with(
            mocker.ANY,  # this is 'self'
            authentication_record=mocker.ANY,
            cache_persistence_options=mocker.ANY,
            prompt_callback=mocker.ANY,
        )

        # Remove the authentication record
        authentication_record_path.unlink(missing_ok=True)
