import os

import jwt
import pytest
from azure.core.credentials import AccessToken
from azure.identity import (
    AuthenticationRecord,
    AzureCliCredential,
    DeviceCodeCredential,
)

from data_safe_haven.external.api.credentials import GraphApiCredential


def pytest_configure():
    """Define constants for use across multiple tests"""
    pytest.subscription_id = "64954419-0f4b-4f6f-bd76-0d4de6ca8b83"
    pytest.user_upn = "username@example.com"
    pytest.user_id = "80b4ccfd-73ef-41b7-bb22-8ec268ec040b"


@pytest.fixture
def authentication_record():
    return AuthenticationRecord(
        tenant_id=pytest.guid_tenant,
        client_id="14d82eec-204b-4c2f-b7e8-296a70dab67e",
        authority="login.microsoftonline.com",
        home_account_id=pytest.user_id,
        username=pytest.user_upn,
    )


@pytest.fixture
def azure_cli_token():
    return jwt.encode(
        {
            "name": "username",
            "oid": pytest.user_id,
            "upn": pytest.user_upn,
            "tid": pytest.guid_tenant,
        },
        "key",
    )


@pytest.fixture
def graph_api_token():
    return jwt.encode(
        {
            "scp": "GroupMember.Read.All User.Read.All",
            "tid": pytest.guid_tenant,
        },
        "key",
    )


@pytest.fixture
def mock_azureclicredential_get_token(mocker, azure_cli_token):
    mocker.patch.object(
        AzureCliCredential,
        "get_token",
        return_value=AccessToken(azure_cli_token, 0),
    )


@pytest.fixture
def mock_devicecodecredential_get_token(mocker, graph_api_token):
    mocker.patch.object(
        DeviceCodeCredential,
        "get_token",
        return_value=AccessToken(graph_api_token, 0),
    )


@pytest.fixture
def mock_devicecodecredential_authenticate(mocker, authentication_record):
    mocker.patch.object(
        DeviceCodeCredential,
        "authenticate",
        return_value=authentication_record,
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
