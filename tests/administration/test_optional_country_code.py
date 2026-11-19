"""CSV imports must not require the unused CountryCode field."""

from unittest.mock import Mock

import pytest

from data_safe_haven.administration.users.user_handler import UserHandler
from data_safe_haven.exceptions import DataSafeHavenUserHandlingError


@pytest.mark.parametrize("separator", [",", ";"])
def test_four_column_csv_is_accepted(tmp_path, separator):
    path = tmp_path / "users.csv"
    path.write_text(
        separator.join(["GivenName", "Surname", "Phone", "Email"])
        + "\n"
        + separator.join(["Ada", "Lovelace", "+441234567890", "ada@example.com"])
        + "\n",
        encoding="utf-8",
    )
    handler = UserHandler(context=Mock(), graph_api=Mock())
    handler.entra_users.add = Mock()
    handler.add(path, "sre.example.com")
    handler.entra_users.add.assert_called_once()
    user = handler.entra_users.add.call_args.args[0][0]
    assert user.country is None
    assert user.domain == "sre.example.com"
    assert user.phone_number == "+441234567890"


def test_five_column_csv_retains_existing_country(tmp_path):
    path = tmp_path / "users.csv"
    path.write_text(
        "GivenName;Surname;Phone;Email;CountryCode;Domain\n"
        "Ada;Lovelace;+14155550100;ada@example.com;GB;custom.example.com\n",
        encoding="utf-8",
    )
    handler = UserHandler(context=Mock(), graph_api=Mock())
    handler.entra_users.add = Mock()
    handler.add(path, "default.example.com")
    user = handler.entra_users.add.call_args.args[0][0]
    assert user.country == "GB"
    assert user.domain == "custom.example.com"
    assert user.phone_number == "+14155550100"


def test_blank_country_column_is_not_required(tmp_path):
    path = tmp_path / "users.csv"
    path.write_text(
        "GivenName;Surname;Phone;Email;CountryCode\n"
        "Ada;Lovelace;+441234567890;ada@example.com;\n",
        encoding="utf-8",
    )
    handler = UserHandler(context=Mock(), graph_api=Mock())
    handler.entra_users.add = Mock()
    handler.add(path, "sre.example.com")
    assert handler.entra_users.add.call_args.args[0][0].country is None


def test_phone_remains_a_required_csv_column(tmp_path):
    path = tmp_path / "users.csv"
    path.write_text("GivenName;Surname;Email\nAda;Lovelace;ada@example.com\n")
    handler = UserHandler(context=Mock(), graph_api=Mock())
    handler.entra_users.add = Mock()
    with pytest.raises(
        DataSafeHavenUserHandlingError, match="missing required columns: Phone"
    ):
        handler.add(path, "sre.example.com")
    handler.entra_users.add.assert_not_called()
