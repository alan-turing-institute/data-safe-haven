"""Standalone logging class implemented as a singleton"""

import logging
from datetime import datetime
from typing import Any

from rich.logging import RichHandler
from rich.text import Text

from data_safe_haven.singleton import Singleton
from data_safe_haven.directories import log_dir


class PlainFileHandler(logging.FileHandler):
    """
    Logging handler that cleans messages before sending them to a log file.
    """

    def __init__(self, *args: Any, **kwargs: Any):
        """Constructor"""
        super().__init__(*args, **kwargs)

    @staticmethod
    def strip_formatting(input_string: str) -> str:
        """Strip console markup formatting from a string"""
        text = Text.from_markup(input_string)
        text.spans = []
        return str(text)

    def emit(self, record: logging.LogRecord) -> None:
        """Emit a record without formatting"""
        record.msg = self.strip_formatting(record.msg)
        super().emit(record)


class LoggingSingleton(logging.Logger, metaclass=Singleton):
    """
    Logging singleton that can be used by anything needing logging
    """

    console_handler = RichHandler(
        level=logging.INFO,
        markup=True,
        rich_tracebacks=True,
        show_time=False,
        show_path=False,
        show_level=False,
    )
    console_handler.setFormatter(logging.Formatter(r"%(message)s"))

    file_handler = PlainFileHandler(
        f"{log_dir()}/{datetime.now().date()}.log",
        delay=True,
        encoding="utf8",
        mode="a",
    )
    file_handler.setFormatter(
        logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
    )
    file_handler.setLevel("NOTSET")

    def __init__(self) -> None:
        # Construct logger object
        super().__init__(name="data_safe_haven", level=logging.NOTSET)

        # Add handlers
        self.addHandler(self.console_handler)
        self.addHandler(self.file_handler)

        # Disable unnecessarily verbose external logging
        logging.getLogger("azure.core.pipeline.policies").setLevel(logging.ERROR)
        logging.getLogger("azure.identity._credentials").setLevel(logging.ERROR)
        logging.getLogger("azure.identity._internal").setLevel(logging.ERROR)
        logging.getLogger("azure.mgmt.core.policies").setLevel(logging.ERROR)
        logging.getLogger("urllib3.connectionpool").setLevel(logging.ERROR)

    @classmethod
    def set_console_level(cls, level: int | str) -> None:
        cls.console_handler.setLevel(level)

    @classmethod
    def show_console_level(cls) -> None:
        cls.console_handler._log_render.show_level = True

    def parse(self, message: str) -> None:
        """
        Parse a message that starts with a log-level token.

        This function is designed to handle messages from non-Python code inside this package.
        """
        tokens = message.split(":")
        level, remainder = tokens[0].upper(), ":".join(tokens[1:]).strip()
        if level == "CRITICAL":
            return self.critical(remainder)
        elif level == "ERROR":
            return self.error(remainder)
        elif level == "WARNING":
            return self.warning(remainder)
        elif level == "INFO":
            return self.info(remainder)
        elif level == "DEBUG":
            return self.debug(remainder)
        else:
            return self.info(message.strip())


class NonLoggingSingleton(logging.Logger, metaclass=Singleton):
    """
    Non-logging singleton that can be used by anything needing logs to be consumed
    """

    def __init__(self) -> None:
        super().__init__(name="non-logger", level=logging.CRITICAL + 10)
        while self.handlers:
            self.removeHandler(self.handlers[0])
