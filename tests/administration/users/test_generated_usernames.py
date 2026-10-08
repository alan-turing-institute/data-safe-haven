"""Entra-compatible generated usernames and safe batch creation."""

import pytest

from data_safe_haven.administration.users import UserHandler
from data_safe_haven.administration.users.research_user import ResearchUser
from data_safe_haven.exceptions import DataSafeHavenUserHandlingError


@pytest.mark.parametrize(
    ("given", "surname", "expected"),
    [
        ("Özge", "García Márquez", "ozge.garcia-marquez"),
        ("Łukasz", "Żółć", "lukasz.zolc"),
        ("Anne-Marie", "Smith-Jones", "anne-marie.smith-jones"),
        ("João", "da Silva", "joao.da-silva"),
        ("D\u2019Arcy", "O'Neill", "darcy.oneill"),
        ("Ægir", "Søndergaard", "aegir.sondergaard"),
        ("  Anna  María  ", "  de   la  Cruz ", "anna-maria.de-la-cruz"),
    ],
)
def test_username_is_ascii_safe_and_preserves_multi_part_surnames(
    given, surname, expected
):
    user = ResearchUser(given_name=given, surname=surname)
    assert user.username == expected
    assert user.display_name == f"{given} {surname}"


def test_explicit_sam_account_name_is_preserved():
    user = ResearchUser(
        given_name="Łukasz", surname="Żółć", sam_account_name="existing_login"
    )
    assert user.username == "existing_login"


@pytest.mark.parametrize(
    ("given", "surname"),
    [(None, "Surname"), ("Jane", ""), ("李", "张")],
)
def test_unsupported_or_missing_names_raise_before_network(given, surname):
    user = ResearchUser(given_name=given, surname=surname)
    with pytest.raises(ValueError):
        _ = user.username


def test_overlong_generated_username_is_rejected():
    user = ResearchUser(given_name="a" * 40, surname="b" * 40)
    with pytest.raises(ValueError, match="64-character"):
        _ = user.username


def _csv(tmp_path, entries):
    path = tmp_path / "users.csv"
    path.write_text(
        "GivenName,Surname,Phone,Email,CountryCode\n"
        + "".join(
            f"{given},{surname},+441234567890,{email},GB\n"
            for given, surname, email in entries
        ),
        encoding="utf-8",
    )
    return path


def test_batch_rejects_transliteration_collisions_before_any_api_call(tmp_path, mocker):
    handler = object.__new__(UserHandler)
    handler.entra_users = mocker.Mock()
    handler.logger = mocker.Mock()
    batch = _csv(
        tmp_path,
        [
            ("Jose", "Garcia", "jose@example.net"),
            ("José", "Garcia", "jose2@example.net"),
        ],
    )
    with pytest.raises(DataSafeHavenUserHandlingError, match=r"jose\.garcia"):
        handler.add(batch, "example.net")
    handler.entra_users.add.assert_not_called()


def test_batch_add_returns_only_successfully_processed_users(tmp_path, mocker):
    handler = object.__new__(UserHandler)
    handler.entra_users = mocker.Mock()
    handler.logger = mocker.Mock()
    batch = _csv(
        tmp_path,
        [
            ("Özge", "Müller", "ozge@example.net"),
            ("Jean", "Dupond", "jean@example.net"),
        ],
    )
    result = handler.add(batch, "example.net")
    assert [user.username for user in result] == ["ozge.muller", "jean.dupond"]
    handler.entra_users.add.assert_called_once_with(result)


def test_failed_graph_api_does_not_report_success(tmp_path, mocker):
    handler = object.__new__(UserHandler)
    handler.entra_users = mocker.Mock()
    handler.logger = mocker.Mock()
    handler.entra_users.add.side_effect = RuntimeError("Graph write failed")
    batch = _csv(tmp_path, [("Jane", "Doe", "jane@example.net")])
    with pytest.raises(RuntimeError, match="Graph write failed"):
        handler.add(batch, "example.net")
