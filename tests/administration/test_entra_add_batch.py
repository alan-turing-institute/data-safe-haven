"""Batch user creation must continue past per-user errors."""

from unittest.mock import Mock

import pytest

from data_safe_haven.administration.users.entra_users import ResilientEntraUsers
from data_safe_haven.administration.users.research_user import ResearchUser
from data_safe_haven.administration.users.user_handler import UserHandler
from data_safe_haven.exceptions import (
    DataSafeHavenEntraIDError,
    DataSafeHavenMicrosoftGraphError,
)


def new_user(given_name, *, domain="example.com", email=True, phone=True):
    return ResearchUser(
        account_enabled=True,
        domain=domain,
        email_address=f"{given_name}@example.com" if email else None,
        given_name=given_name,
        phone_number="+442011112222" if phone else None,
        surname="Researcher",
    )


@pytest.fixture
def api():
    graph = Mock()
    graph.read_domains.return_value = [
        {"id": "example.com", "isVerified": True},
        {"id": "unverified.com", "isVerified": False},
    ]
    return graph


def test_single_graph_error_does_not_block_remaining_users(api):
    attempted = []

    def create(request, email, phone):
        attempted.append((request["userPrincipalName"], email, phone))
        if request["mailNickname"] == "broken.researcher":
            msg = "Graph rejected the request"
            raise DataSafeHavenMicrosoftGraphError(msg)

    api.create_user.side_effect = create
    users = [new_user("first"), new_user("broken"), new_user("third")]
    with pytest.raises(DataSafeHavenEntraIDError) as exc:
        ResilientEntraUsers(api).add(users)

    assert [name for name, _, _ in attempted] == [
        "first.researcher@example.com",
        "broken.researcher@example.com",
        "third.researcher@example.com",
    ]
    assert "2 of 3" in str(exc.value)
    assert "broken.researcher@example.com" in str(exc.value)
    assert "Graph rejected the request" in str(exc.value)
    assert "first.researcher@example.com" not in str(exc.value)


def test_invalid_domain_and_missing_fields_fail_individually(api):
    users = [
        new_user("domain", domain="unverified.com"),
        new_user("email", email=False),
        new_user("phone", phone=False),
        new_user("valid"),
    ]
    with pytest.raises(DataSafeHavenEntraIDError) as exc:
        ResilientEntraUsers(api).add(users)

    assert "1 of 4" in str(exc.value)
    assert "domain.researcher@unverified.com" in str(exc.value)
    assert "email.researcher@example.com" in str(exc.value)
    assert "phone.researcher@example.com" in str(exc.value)
    api.create_user.assert_called_once()
    assert api.create_user.call_args.args[0]["mailNickname"] == "valid.researcher"


def test_unexpected_per_user_error_does_not_leak_secrets(api):
    api.create_user.side_effect = [
        RuntimeError("request body includes confidential credential"),
        None,
    ]
    with pytest.raises(DataSafeHavenEntraIDError) as exc:
        ResilientEntraUsers(api).add([new_user("first"), new_user("second")])

    assert api.create_user.call_count == 2
    assert "1 of 2" in str(exc.value)
    assert "RuntimeError" in str(exc.value)
    assert "confidential credential" not in str(exc.value)


def test_csv_handler_uses_failure_isolating_user_manager(api):
    handler = UserHandler(context=Mock(), graph_api=api)
    assert isinstance(handler.entra_users, ResilientEntraUsers)


def test_all_success_and_empty_batch(api):
    manager = ResilientEntraUsers(api)
    manager.add([])
    api.read_domains.assert_not_called()
    manager.add([new_user("one"), new_user("two")])
    assert api.read_domains.call_count == 2
    assert api.create_user.call_count == 2


def test_domain_lookup_failure_prevents_all_user_writes(api):
    api.read_domains.side_effect = DataSafeHavenMicrosoftGraphError("Permission denied")
    with pytest.raises(DataSafeHavenEntraIDError, match="Permission denied"):
        ResilientEntraUsers(api).add([new_user("first")])
    api.create_user.assert_not_called()
