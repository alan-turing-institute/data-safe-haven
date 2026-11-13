"""Explicit logging at CLI boundaries, with no exception-constructor side effect."""

import logging

from data_safe_haven.exceptions import (
    DataSafeHavenAzureError,
    DataSafeHavenConfigError,
)
from data_safe_haven.logging import log_unhandled_dsh_exception


def test_reporting_is_explicit_and_escapes_newlines(caplog):
    with caplog.at_level(logging.DEBUG, logger="data_safe_haven"):
        exc = DataSafeHavenConfigError("invalid\nconfiguration")
        assert not caplog.records
        log_unhandled_dsh_exception(exc)

    assert [record.getMessage() for record in caplog.records] == [
        r"invalid\nconfiguration"
    ]


def test_reporting_logs_the_dsh_cause_chain_once(caplog):
    inner = DataSafeHavenAzureError("token acquisition failed")
    outer = DataSafeHavenConfigError("config download failed")
    outer.__cause__ = inner
    with caplog.at_level(logging.DEBUG, logger="data_safe_haven"):
        assert not caplog.records
        log_unhandled_dsh_exception(outer)
    assert [record.getMessage() for record in caplog.records] == [
        "token acquisition failed",
        "config download failed",
    ]


def test_reporting_handles_utf8_bytes_and_empty_messages(caplog):
    with caplog.at_level(logging.DEBUG, logger="data_safe_haven"):
        log_unhandled_dsh_exception(DataSafeHavenConfigError(b"caf\xc3\xa9"))
        log_unhandled_dsh_exception(DataSafeHavenConfigError(""))
    assert [record.getMessage() for record in caplog.records] == ["café"]
