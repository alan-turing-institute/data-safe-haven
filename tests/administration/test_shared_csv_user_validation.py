"""Keep add and set user CSV validation consistent."""

from unittest.mock import Mock

import pytest

from data_safe_haven.administration.users.user_handler import UserHandler
from data_safe_haven.exceptions import DataSafeHavenUserHandlingError


@pytest.fixture
def handler():
    handler = UserHandler(context=Mock(), graph_api=Mock())
    handler.entra_users.add = Mock()
    handler.entra_users.set = Mock()
    handler.entra_users.list = Mock(return_value=[])
    return handler


@pytest.mark.parametrize("operation", ["add", "set"])
def test_rejects_invalid_later_row_before_any_remote_change(
    handler, tmp_path, operation
):
    csv_path = tmp_path / "users.csv"
    csv_path.write_text(
        "GivenName;Surname;Phone;Email\n"
        "Ada;Lovelace;+441234567890;ada@example.com\n"
        "Grace;Hopper;+441234567891;\n",
        encoding="utf-8",
    )
    with pytest.raises(
        DataSafeHavenUserHandlingError,
        match=r"file line 3 \(data row 2\) is missing values for: Email",
    ):
        if operation == "add":
            handler.add(csv_path, "example.org")
        else:
            handler.set(str(csv_path))
    handler.entra_users.add.assert_not_called()
    handler.entra_users.list.assert_not_called()
    handler.entra_users.set.assert_not_called()


@pytest.mark.parametrize("operation", ["add", "set"])
def test_rejects_unexpected_header_before_remote_change(handler, tmp_path, operation):
    csv_path = tmp_path / "users.csv"
    csv_path.write_text(
        "GivenName,Surname,Phone,Email,Unknown\n"
        "Ada,Lovelace,+441234567890,ada@example.com,extra\n",
        encoding="utf-8",
    )
    with pytest.raises(
        DataSafeHavenUserHandlingError, match="unexpected columns: Unknown"
    ):
        if operation == "add":
            handler.add(csv_path, "example.org")
        else:
            handler.set(str(csv_path))
    handler.entra_users.add.assert_not_called()
    handler.entra_users.set.assert_not_called()


def test_set_accepts_semicolon_csv_with_legacy_gb_default(handler, tmp_path):
    csv_path = tmp_path / "users.csv"
    csv_path.write_text(
        "GivenName;Surname;Phone;Email\n"
        "Ada;Lovelace;+441234567890;ada@example.com\n",
        encoding="utf-8",
    )
    handler.set(str(csv_path))
    handler.entra_users.set.assert_called_once()
    (user,) = handler.entra_users.set.call_args.args[0]
    assert user.country == "GB"
    assert user.account_enabled is None
    assert user.username == "ada.lovelace"
    handler.entra_users.add.assert_not_called()


def test_set_honours_explicit_optional_country(handler, tmp_path):
    csv_path = tmp_path / "users.csv"
    csv_path.write_text(
        "GivenName,Surname,Phone,Email,CountryCode\n"
        "Ada,Lovelace,+14155550100,ada@example.com,US\n",
        encoding="utf-8",
    )
    handler.set(str(csv_path))
    (user,) = handler.entra_users.set.call_args.args[0]
    assert user.country == "US"


def test_set_missing_file_reports_read_error(handler, tmp_path):
    with pytest.raises(
        DataSafeHavenUserHandlingError, match="Could not read users CSV"
    ):
        handler.set(str(tmp_path / "missing.csv"))
    handler.entra_users.set.assert_not_called()
