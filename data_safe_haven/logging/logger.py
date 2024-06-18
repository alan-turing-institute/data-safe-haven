"""Standalone logging class implemented as a singleton"""

import logging
from datetime import UTC, datetime
from typing import Any

from rich.logging import RichHandler
from rich.text import Text

from data_safe_haven.directories import log_dir


def init_logging():
    # Configure root handler
    logger = get_logger()
    logger.setLevel(logging.NOTSET)

    console_handler = RichHandler(
        level=logging.INFO,
        markup=True,
        rich_tracebacks=True,
        show_time=False,
        show_path=False,
        show_level=False,
    )
    console_handler.setFormatter(logging.Formatter(r"%(message)s"))

    log_directory = str(log_dir())
    log_file = str(datetime.now(UTC).date()) + ".log"
    file_handler = PlainFileHandler(
        (log_directory + "/" + log_file),
        # f"{log_dir()}/{datetime.now(UTC).date()}.log",
        # f"what.log",
        delay=True,
        encoding="utf8",
        mode="a",
    )
    file_handler.setFormatter(
        logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
    )
    file_handler.setLevel(logging.NOTSET)

    # Add handlers
    logger.addHandler(console_handler)
    logger.console_handler = console_handler
    logger.addHandler(file_handler)
    logger.file_handler = file_handler

    # Disable unnecessarily verbose external logging
    logging.getLogger("azure.core.pipeline.policies").setLevel(logging.ERROR)
    logging.getLogger("azure.identity._credentials").setLevel(logging.ERROR)
    logging.getLogger("azure.identity._internal").setLevel(logging.ERROR)
    logging.getLogger("azure.mgmt.core.policies").setLevel(logging.ERROR)
    logging.getLogger("urllib3.connectionpool").setLevel(logging.ERROR)


def get_logger() -> logging.Logger:
    return logging.getLogger(None)


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


def set_console_level(level: int | str) -> None:
    # print(get_logger().handlers)
    # print(get_logger().handlers[0].__dict__)
    get_logger().console_handler.setLevel(level)
    # for handler in get_logger().handlers:
    #     if isinstance(handler, RichHandler):
    #         handler.setLevel(level)


def show_console_level() -> None:
    get_logger().console_handler._log_render.show_level = True
    # for handler in get_logger().handlers:
    #     if isinstance(handler, RichHandler):
    #         handler._log_render.show_level = True


def parse(message: str) -> None:
    """
    Parse a message that starts with a log-level token.

    This function is designed to handle messages from non-Python code inside this package.
    """
    logger = get_logger()
    tokens = message.split(":")
    level, remainder = tokens[0].upper(), ":".join(tokens[1:]).strip()
    if level == "CRITICAL":
        return logger.critical(remainder)
    elif level == "ERROR":
        return logger.error(remainder)
    elif level == "WARNING":
        return logger.warning(remainder)
    elif level == "INFO":
        return logger.info(remainder)
    elif level == "DEBUG":
        return logger.debug(remainder)
    else:
        return logger.info(message.strip())
