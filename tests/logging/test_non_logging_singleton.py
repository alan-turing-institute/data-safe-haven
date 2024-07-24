import logging

import pytest

from data_safe_haven.logging import get_null_logger
from data_safe_haven.logging.non_logging_singleton import NonLoggingSingleton
from data_safe_haven.singleton import Singleton


class TestNonLoggingSingleton:
    def test_constructor(self):
        logger = get_null_logger()
        assert isinstance(logger, NonLoggingSingleton)
        assert type(logger.__class__) is Singleton

    @pytest.mark.parametrize(
        "level",
        [
            "debug",
            "info",
            "warning",
            "error",
            "critical",
            "fatal",
        ],
    )
    def test_output_is_none(self, level, capsys):
        logger = get_null_logger()
        getattr(logger, level)("Hello world!")
        stdout, stderr = capsys.readouterr()
        assert stdout == ""
        assert stderr == ""

    def test_default_level(self):
        logger = get_null_logger()
        assert logger.level > logging.CRITICAL
