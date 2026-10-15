"""Validate user CSVs before creating accounts in Microsoft Entra ID."""

from unittest.mock import Mock

import pytest

from data_safe_haven.administration.users.user_handler import UserHandler
from data_safe_haven.exceptions import DataSafeHavenUserHandlingError


@pytest.fixture
def handler(mocker):
    user_handler = UserHandler(mocker.Mock(), mocker.Mock())
    user_handler.entra_users.add = Mock()
    return user_handler


def test_reports_missing_email_column_without_calling_entra(handler, tmp_path):
    csv_file = tmp_path / "users.csv"
    csv_file.write_text(
        "GivenName,Surname,Phone,CountryCode\nAda,Lovelace,+441234567890,GB\n"
    )

    with pytest.raises(
        DataSafeHavenUserHandlingError,
        match="missing required columns: Email",
    ):
        handler.add(csv_file, "example.org")

    handler.entra_users.add.assert_not_called()


@pytest.mark.parametrize("missing_value", ("", "   "))
def test_blank_optional_country_code_is_accepted(handler, tmp_path, missing_value):
    csv_file = tmp_path / "users.csv"
    csv_file.write_text(
        "GivenName,Surname,Phone,Email,CountryCode\n"
        f"Ada,Lovelace,+441234567890,ada@example.org,{missing_value}\n"
    )
    handler.add(csv_file, "example.org")
    handler.entra_users.add.assert_called_once()
    (user,) = handler.entra_users.add.call_args.args[0]
    assert user.country is None


def test_reports_missing_field_in_later_row_before_creating_any_user(handler, tmp_path):
    csv_file = tmp_path / "users.csv"
    csv_file.write_text(
        "GivenName,Surname,Phone,Email,CountryCode\n"
        "Ada,Lovelace,+441234567890,ada@example.org,GB\n"
        "Grace,Hopper,+441234567891,,GB\n"
    )

    with pytest.raises(
        DataSafeHavenUserHandlingError,
        match=r"file line 3 \(data row 2\) is missing values for: Email",
    ):
        handler.add(csv_file, "example.org")

    handler.entra_users.add.assert_not_called()


def test_reports_extra_values(handler, tmp_path):
    csv_file = tmp_path / "users.csv"
    csv_file.write_text(
        "GivenName,Surname,Phone,Email,CountryCode\n"
        "Ada,Lovelace,+441234567890,ada@example.org,GB,unexpected\n"
    )

    with pytest.raises(
        DataSafeHavenUserHandlingError,
        match=r"file line 2 \(data row 1\) contains extra values",
    ):
        handler.add(csv_file, "example.org")

    handler.entra_users.add.assert_not_called()


def test_reports_unexpected_csv_headers_before_creating_users(handler, tmp_path):
    csv_file = tmp_path / "users.csv"
    csv_file.write_text(
        "GivenName,Surname,Phone,Email,CountryCode,Unexpected\n"
        "Ada,Lovelace,+441234567890,ada@example.org,GB,extra\n"
    )
    with pytest.raises(
        DataSafeHavenUserHandlingError,
        match="unexpected columns: Unexpected",
    ):
        handler.add(csv_file, "example.org")
    handler.entra_users.add.assert_not_called()


def test_accepts_semicolon_delimited_valid_rows(handler, tmp_path):
    csv_file = tmp_path / "users.csv"
    csv_file.write_text(
        "GivenName;Surname;Phone;Email;CountryCode\n"
        "Ada;Lovelace;+441234567890;ada@example.org;GB\n"
    )

    handler.add(csv_file, "example.org")

    handler.entra_users.add.assert_called_once()
    (user,) = handler.entra_users.add.call_args.args[0]
    assert (user.given_name, user.surname, user.country) == (
        "Ada",
        "Lovelace",
        "GB",
    )
    assert (user.email_address, user.domain) == (
        "ada@example.org",
        "example.org",
    )


def test_missing_file_is_an_actionable_error(handler, tmp_path):
    with pytest.raises(
        DataSafeHavenUserHandlingError,
        match="Could not read users CSV",
    ):
        handler.add(tmp_path / "missing.csv", "example.org")

    handler.entra_users.add.assert_not_called()


def test_invalid_utf8_reports_format_without_disclosing_contents(handler, tmp_path):
    csv_file = tmp_path / "users.csv"
    csv_file.write_bytes(
        b"GivenName,Surname,Phone,Email,CountryCode\nAda,\xff,123,a@b,GB\n"
    )

    with pytest.raises(
        DataSafeHavenUserHandlingError,
        match="expected UTF-8 text",
    ):
        handler.add(csv_file, "example.org")

    handler.entra_users.add.assert_not_called()
