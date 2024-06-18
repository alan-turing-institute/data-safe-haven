import logging
from datetime import datetime
from pathlib import Path

from rich.logging import RichHandler

from data_safe_haven.logging.logger import PlainFileHandler, get_logger, logfile_name, set_console_level, show_console_level


class TestPlainFileHandler:
    def test_strip_formatting(self):
        assert PlainFileHandler.strip_formatting("[green]hello[/]") == "hello"


class TestLogFileName:
    def test_logfile_name(self):
        name = logfile_name()
        assert name.endswith(".log")
        date = name.split(".")[0]
        assert datetime.strptime(date, "%Y-%m-%d")  # noqa: DTZ007


class TestGetLogger:
    def test_get_logger(self):
        logger = get_logger()
        assert isinstance(logger, logging.Logger)
        assert logger.name == "data_safe_haven"
        assert hasattr(logger, "console_handler")
        assert hasattr(logger, "file_handler")


class TestLogger:
    def test_constructor(self, log_directory):
        logger = get_logger()

        assert isinstance(logger.file_handler, PlainFileHandler)
        assert isinstance(logger.console_handler, RichHandler)

        assert logger.file_handler.baseFilename == f"{log_directory}/test.log"
        log_file = Path(logger.file_handler.baseFilename)
        logger.info("hello")
        assert log_file.is_file()


class TestSetConsoleLevel:
    def test_set_console_level(self):
        logger = get_logger()
        assert logger.console_handler.level == logging.INFO
        set_console_level(logging.DEBUG)
        assert logger.console_handler.level == logging.DEBUG


class TestShowConsoleLevel:
    def test_show_console_level(self):
        logger = get_logger()
        assert not logger.console_handler._log_render.show_level
        show_console_level()
        assert logger.console_handler._log_render.show_level
