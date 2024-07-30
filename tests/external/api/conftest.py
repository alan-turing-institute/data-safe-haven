import datetime
import os

import jwt
import pytest
from azure.core.credentials import AccessToken
from azure.identity import (
    AuthenticationRecord,
    AzureCliCredential,
    DeviceCodeCredential,
)

from data_safe_haven.external import GraphApi
from data_safe_haven.external.api.credentials import GraphApiCredential


def pytest_configure(config):
    """Define constants for use across multiple tests"""
    config.user_upn = "username@example.com"


@pytest.fixture
def authentication_record(request):
    return AuthenticationRecord(
        tenant_id=request.config.guid_tenant,
        client_id="14d82eec-204b-4c2f-b7e8-296a70dab67e",
        authority="login.microsoftonline.com",
        home_account_id=request.config.guid_user,
        username=request.config.user_upn,
    )


@pytest.fixture
def azure_cli_token(request):
    return jwt.encode(
        {
            "name": "username",
            "oid": request.config.guid_user,
            "upn": request.config.user_upn,
            "tid": request.config.guid_tenant,
        },
        "key",
    )


@pytest.fixture
def graph_api_token(request):
    return jwt.encode(
        {
            "scp": "GroupMember.Read.All User.Read.All",
            "tid": request.config.guid_tenant,
        },
        "key",
    )


@pytest.fixture
def mock_authenticationrecord_deserialize(mocker, authentication_record):
    return mocker.patch.object(
        AuthenticationRecord,
        "deserialize",
        return_value=authentication_record,
    )


@pytest.fixture
def mock_azureclicredential_get_token(mocker, azure_cli_token):
    return mocker.patch.object(
        AzureCliCredential,
        "get_token",
        return_value=AccessToken(azure_cli_token, 0),
    )


@pytest.fixture
def mock_azureclicredential_get_token_invalid(mocker):
    return mocker.patch.object(
        AzureCliCredential,
        "get_token",
        return_value=AccessToken("not a jwt", 0),
    )


@pytest.fixture
def mock_devicecodecredential_authenticate(mocker, authentication_record):
    return mocker.patch.object(
        DeviceCodeCredential,
        "authenticate",
        return_value=authentication_record,
    )


@pytest.fixture
def mock_devicecodecredential_get_token(mocker, graph_api_token):
    return mocker.patch.object(
        DeviceCodeCredential,
        "get_token",
        return_value=AccessToken(graph_api_token, 0),
    )


@pytest.fixture
def mock_devicecodecredential_new(mocker, authentication_record):
    class MockDeviceCodeCredential:
        def __init__(self, *args, prompt_callback, **kwargs):  # noqa: ARG002
            self.prompt_callback = prompt_callback

        def authenticate(self, *args, **kwargs):  # noqa: ARG002
            self.prompt_callback(
                "VERIFICATION_URI",
                "USER_DEVICE_CODE",
                datetime.datetime.now(tz=datetime.UTC),
            )
            return authentication_record

    mocker.patch.object(
        DeviceCodeCredential,
        "__new__",
        lambda *args, **kwargs: MockDeviceCodeCredential(*args, **kwargs),
    )


@pytest.fixture
def mock_graphapi_read_domains(mocker):
    mocker.patch.object(
        GraphApi,
        "read_domains",
        return_value=[{"id": "example.com"}],
    )


@pytest.fixture
def mock_graphapicredential_get_credential(mocker):
    mocker.patch.object(
        GraphApiCredential,
        "get_credential",
        return_value=DeviceCodeCredential(),
    )


@pytest.fixture
def mock_graphapicredential_get_token(mocker, graph_api_token):
    mocker.patch.object(
        GraphApiCredential,
        "get_token",
        return_value=AccessToken(graph_api_token, 0),
    )


@pytest.fixture
def tmp_config_dir(mocker, tmp_path):
    mocker.patch.dict(os.environ, {"DSH_CONFIG_DIRECTORY": str(tmp_path)})
