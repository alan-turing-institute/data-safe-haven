import jwt
import pytest
from azure.core.credentials import AccessToken
from azure.identity import AzureCliCredential
from pytest import fixture


def pytest_configure():
    """Define constants for use across multiple tests"""
    pytest.user_id = "80b4ccfd-73ef-41b7-bb22-8ec268ec040b"


@fixture
def jwt_token():
    return jwt.encode(
        {
            "name": "username",
            "oid": pytest.user_id,
            "upn": "username@example.com",
            "tid": pytest.guid_tenant,
        },
        "key",
    )


@fixture
def mock_azureclicredential_get_token(mocker, jwt_token):
    mocker.patch.object(
        AzureCliCredential,
        "get_token",
        return_value=AccessToken(jwt_token, 0),
    )
