"""Exception creation and handling must not log recoverable failures."""

import logging

import pytest

from data_safe_haven.exceptions import (
    DataSafeHavenAzureError,
    DataSafeHavenConfigError,
    DataSafeHavenError,
    DataSafeHavenPulumiError,
)
from data_safe_haven.serialisers import YAMLSerialisableModel


@pytest.mark.parametrize(
    "exception_type",
    [
        DataSafeHavenError,
        DataSafeHavenConfigError,
        DataSafeHavenAzureError,
        DataSafeHavenPulumiError,
    ],
)
def test_constructing_dsh_exception_does_not_log(exception_type, caplog):
    with caplog.at_level(logging.DEBUG, logger="data_safe_haven"):
        exc = exception_type("Expected failure\nwhich may be handled")
    assert exc.args == ("Expected failure\nwhich may be handled",)
    assert not caplog.records


def test_caught_missing_config_error_is_silent(caplog):
    with caplog.at_level(logging.DEBUG, logger="data_safe_haven"):
        try:
            message = "Missing optional file"
            raise DataSafeHavenConfigError(message)
        except DataSafeHavenConfigError:
            # A fallback configuration is a normal, handled situation.
            pass
    assert not caplog.records


def test_bytes_messages_and_exception_chains_are_preserved(caplog):
    with caplog.at_level(logging.DEBUG, logger="data_safe_haven"):
        try:
            try:
                message = "parse failed"
                raise ValueError(message)
            except ValueError as exc:
                message = b"invalid configuration"
                raise DataSafeHavenConfigError(message) from exc
        except DataSafeHavenConfigError as exc:
            assert exc.args == (b"invalid configuration",)
            assert isinstance(exc.__cause__, ValueError)
    assert not caplog.records


def test_handled_missing_yaml_file_emits_no_log(caplog, tmp_path):
    with caplog.at_level(logging.DEBUG, logger="data_safe_haven"):
        try:
            YAMLSerialisableModel.from_filepath(tmp_path / "optional.yaml")
        except DataSafeHavenConfigError:
            # The caller may create a default file instead.
            pass
    assert not caplog.records
