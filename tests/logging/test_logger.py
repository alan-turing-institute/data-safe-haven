from os import getenv
from pathlib import Path

from freezegun import freeze_time
from rich.logging import RichHandler

from data_safe_haven.directories import log_dir
from data_safe_haven.logging.logger import LoggingSingleton, PlainFileHandler


class TestPlainFileHandler:
    def test_strip_formatting(self):
        assert PlainFileHandler.strip_formatting("[green]hello[/]") == "hello"


class TestLoggingSingleton:
    @freeze_time("1am on July 2nd, 2024")
    def test_constructor(self, log_directory):
        logger = LoggingSingleton()

        assert isinstance(logger.file_handler, PlainFileHandler)
        assert isinstance(logger.console_handler, RichHandler)

        print(getenv("DSH_LOG_DIRECTORY"))
        print(log_dir())
        print(logger.file_handler.baseFilename)
        print(log_directory)
        assert logger.file_handler.baseFilename == f"{log_directory}/2024-07-02.log"
        log_file = Path(logger.file_handler.baseFilename)
        assert log_file.is_file()
