import pytest
from azure.identity import (
    AzureCliCredential,
    DeviceCodeCredential,
)

from data_safe_haven.directories import config_dir
from data_safe_haven.exceptions import (
    DataSafeHavenAzureError,
    DataSafeHavenCachedCredentialError,
)
from data_safe_haven.external.api.credentials import (
    AzureSdkCredential,
    DeferredCredential,
    GraphApiCredential,
)


class TestAzureSdkCredential:
    def test_confirm_credentials_interactive(
        self,
        mock_confirm_yes,  # noqa: ARG002
        mock_azureclicredential_get_token,  # noqa: ARG002
        capsys,
        request,
    ):
        DeferredCredential.cache_ = set()
        credential = AzureSdkCredential(skip_confirmation=False)
        credential.get_credential()
        out, _ = capsys.readouterr()
        assert "You are logged into the Azure CLI as" in out
        assert f"user: username ({request.config.guid_user})" in out
        assert f"tenant: example.com ({request.config.guid_tenant})" in out

    def test_confirm_credentials_interactive_fail(
        self,
        mock_confirm_no,  # noqa: ARG002
        mock_azureclicredential_get_token,  # noqa: ARG002
        capsys,
    ):
        DeferredCredential.cache_ = set()
        credential = AzureSdkCredential(skip_confirmation=False)
        with pytest.raises(
            DataSafeHavenCachedCredentialError,
            match="Selected credentials are incorrect.",
        ):
            credential.get_credential()
        out, _ = capsys.readouterr()
        assert "Please authenticate with Azure: run 'az login'" in out

    def test_confirm_credentials_interactive_cache(
        self,
        mock_confirm_yes,  # noqa: ARG002
        mock_azureclicredential_get_token,  # noqa: ARG002
        capsys,
        request,
    ):
        DeferredCredential.cache_ = {
            (request.config.guid_user, request.config.guid_tenant)
        }
        credential = AzureSdkCredential(skip_confirmation=False)
        credential.get_credential()
        out, _ = capsys.readouterr()
        assert "You are logged into the Azure CLI as" not in out

    def test_decode_token_error(
        self, mock_azureclicredential_get_token_invalid  # noqa: ARG002
    ):
        credential = AzureSdkCredential(skip_confirmation=True)
        with pytest.raises(
            DataSafeHavenAzureError,
            match="Error getting account information from Azure CLI.",
        ):
            credential.decode_token(credential.token)

    def test_get_credential(self, mock_azureclicredential_get_token):  # noqa: ARG002
        credential = AzureSdkCredential(skip_confirmation=True)
        assert isinstance(credential.get_credential(), AzureCliCredential)

    def test_get_token(self, mock_azureclicredential_get_token):  # noqa: ARG002
        credential = AzureSdkCredential(skip_confirmation=True)
        assert isinstance(credential.token, str)

    def test_decode_token(
        self,
        request,
        mock_azureclicredential_get_token,  # noqa: ARG002
    ):
        credential = AzureSdkCredential(skip_confirmation=True)
        decoded = credential.decode_token(credential.token)
        assert decoded["name"] == "username"
        assert decoded["oid"] == request.config.guid_user
        assert decoded["upn"] == "username@example.com"
        assert decoded["tid"] == request.config.guid_tenant


class TestGraphApiCredential:
    def test_authentication_record_is_used(
        self,
        request,
        authentication_record,
        mock_authenticationrecord_deserialize,
        mock_devicecodecredential_authenticate,  # noqa: ARG002
        tmp_config_dir,  # noqa: ARG002
    ):
        # Write an authentication record
        cache_name = f"dsh-{request.config.guid_tenant}"
        authentication_record_path = (
            config_dir() / f".msal-authentication-cache-{cache_name}"
        )
        serialised_record = authentication_record.serialize()
        with open(authentication_record_path, "w") as f_auth:
            f_auth.write(serialised_record)

        # Get a credential
        credential = GraphApiCredential(
            request.config.guid_tenant, skip_confirmation=True
        )
        credential.get_credential()

        # Remove the authentication record
        authentication_record_path.unlink(missing_ok=True)

        mock_authenticationrecord_deserialize.assert_called_once_with(serialised_record)

    def test_decode_token(
        self,
        request,
        mock_graphapicredential_get_token,  # noqa: ARG002
    ):
        credential = GraphApiCredential(
            request.config.guid_tenant, skip_confirmation=True
        )
        decoded = credential.decode_token(credential.token)
        assert decoded["scp"] == "GroupMember.Read.All User.Read.All"
        assert decoded["tid"] == request.config.guid_tenant

    def test_get_credential(
        self,
        request,
        mock_devicecodecredential_authenticate,  # noqa: ARG002
        mock_devicecodecredential_get_token,  # noqa: ARG002
        tmp_config_dir,  # noqa: ARG002
    ):
        credential = GraphApiCredential(
            request.config.guid_tenant, skip_confirmation=True
        )
        assert isinstance(credential.get_credential(), DeviceCodeCredential)

    def test_get_credential_callback(
        self,
        capsys,
        request,
        mock_devicecodecredential_new,  # noqa: ARG002
        tmp_config_dir,  # noqa: ARG002
    ):
        credential = GraphApiCredential(
            request.config.guid_tenant, skip_confirmation=True
        )
        credential.get_credential()
        captured = capsys.readouterr()
        cleaned_stdout = " ".join(captured.out.split())
        assert (
            "Go to VERIFICATION_URI in a web browser and enter the code USER_DEVICE_CODE at the prompt."
            in cleaned_stdout
        )

    def test_get_token(
        self,
        request,
        mock_devicecodecredential_get_token,  # noqa: ARG002
        mock_graphapicredential_get_credential,  # noqa: ARG002
    ):
        credential = GraphApiCredential(
            request.config.guid_tenant, skip_confirmation=True
        )
        assert isinstance(credential.token, str)
