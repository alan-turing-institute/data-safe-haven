import logging
from datetime import datetime
from pathlib import Path

from rich.logging import RichHandler

from data_safe_haven.logging.logger import (
    PlainFileHandler,
    get_console_handler,
    get_logger,
    logfile_name,
    set_console_level,
    show_console_level,
)


class TestLogFileName:
    def test_logfile_name(self):
        name = logfile_name()
        assert name.endswith(".log")
        date = name.split(".")[0]
        assert datetime.strptime(date, "%Y-%m-%d")  # noqa: DTZ007


class TestGetConsoleHandler:
    def test_get_console_handler(self):
        handler = get_console_handler()
        assert isinstance(handler, RichHandler)
        assert handler.level == logging.INFO


class TestGetLogger:
    def test_get_logger(self):
        logger = get_logger()
        assert isinstance(logger, logging.Logger)
        assert logger.name == "data_safe_haven"


class TestLogger:
    def test_constructor(self, log_directory):
        logger = get_logger()
        file_handler = next(
            h for h in logger.handlers if isinstance(h, PlainFileHandler)
        )

        assert file_handler
        assert file_handler.level == logging.NOTSET
        assert file_handler.baseFilename == f"{log_directory}/test.log"

    def test_info(self, capsys):
        logger = get_logger()
        file_handler = next(
            h for h in logger.handlers if isinstance(h, PlainFileHandler)
        )
        log_file = Path(file_handler.baseFilename)

        logger.info("hello")
        out, _ = capsys.readouterr()

        assert "hello" in out
        assert log_file.is_file()


class TestSetConsoleLevel:
    def test_set_console_level(self):
        handler = get_console_handler()
        assert handler.level == logging.INFO
        set_console_level(logging.DEBUG)
        assert handler.level == logging.DEBUG

    def test_set_console_level_stdout(self, capsys):
        logger = get_logger()
        set_console_level(logging.DEBUG)
        logger.debug("hello")
        out, _ = capsys.readouterr()
        assert "hello" in out


class TestShowConsoleLevel:
    def test_show_console_level(self):
        handler = get_console_handler()
        assert not handler._log_render.show_level
        show_console_level()
        assert handler._log_render.show_level

    def test_show_console_level_stdout(self, capsys):
        logger = get_logger()
        show_console_level()
        logger.info("hello")
        out, _ = capsys.readouterr()
        assert "INFO" in out
