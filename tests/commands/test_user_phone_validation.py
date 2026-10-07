"""Reject obviously invalid phone numbers before calling Microsoft Graph."""

import pytest

from data_safe_haven.administration.users.entra_users import EntraUsers
from data_safe_haven.administration.users.research_user import ResearchUser
from data_safe_haven.commands.users import users_command_group
from data_safe_haven.config import SHMConfig
from data_safe_haven.exceptions import DataSafeHavenEntraIDError
from data_safe_haven.external import GraphApi


@pytest.fixture
def graph_api(mocker):
    graph = mocker.Mock()
    graph.read_domains.return_value = [{"id": "example.org", "isVerified": True}]
    return graph


def user(phone_number, *, country="GB", given_name="Ada"):
    return ResearchUser(
        account_enabled=True,
        country=country,
        domain="example.org",
        email_address="ada@example.org",
        given_name=given_name,
        phone_number=phone_number,
        surname="Lovelace",
    )


@pytest.mark.parametrize(
    "phone_number,country",
    [
        ("123", "GB"),
        ("12", "US"),
        ("12345678901234567890", "GB"),
        ("not a number", "GB"),
        ("", "GB"),
        ("   ", "GB"),
        ("07700 900123", None),
    ],
)
def test_invalid_number_prevents_all_graph_calls(graph_api, phone_number, country):
    users = EntraUsers(graph_api)

    with pytest.raises(DataSafeHavenEntraIDError) as exc_info:
        users.add([user(phone_number, country=country)])

    assert "phone number" in str(exc_info.value.__cause__).lower()
    graph_api.read_domains.assert_not_called()
    graph_api.create_user.assert_not_called()


@pytest.mark.parametrize(
    "phone_number,country",
    [
        ("+44 7700 900123", "GB"),
        ("07700 900123", "GB"),
        ("+1 415 555 2671", "US"),
        ("6502530000", "US"),
        ("+44 7700 900123", None),
    ],
)
def test_possible_international_and_regional_numbers_are_preserved(
    graph_api, phone_number, country
):
    EntraUsers(graph_api).add([user(phone_number, country=country)])

    graph_api.read_domains.assert_called_once()
    graph_api.create_user.assert_called_once()
    assert graph_api.create_user.call_args.args[2] == phone_number


def test_invalid_second_user_prevents_creating_first_user(graph_api):
    with pytest.raises(DataSafeHavenEntraIDError):
        EntraUsers(graph_api).add(
            [
                user("+44 7700 900123"),
                user("123", given_name="Grace"),
            ]
        )

    graph_api.read_domains.assert_not_called()
    graph_api.create_user.assert_not_called()


def test_number_validation_does_not_require_a_real_phone_subscription(graph_api):
    """Possibility checks reject malformed lengths, not unallocated numbers."""
    EntraUsers(graph_api).add([user("+44 7700 900123")])
    graph_api.create_user.assert_called_once()


def test_csv_import_reports_invalid_phone_before_creating_any_user(
    mocker, runner, tmp_path, shm_config
):
    csv_path = tmp_path / "users.csv"
    csv_path.write_text(
        "GivenName,Surname,Phone,Email,CountryCode\n"
        "Ada,Lovelace,123,ada@example.org,GB\n",
        encoding="utf-8",
    )
    mocker.patch.object(SHMConfig, "from_remote", return_value=shm_config)
    graph_api = mocker.Mock()
    mocker.patch.object(GraphApi, "from_scopes", return_value=graph_api)

    result = runner.invoke(users_command_group, ["add", str(csv_path)])

    assert result.exit_code == 1
    assert "invalid phone number" in result.stdout.lower()
    graph_api.read_domains.assert_not_called()
    graph_api.create_user.assert_not_called()
