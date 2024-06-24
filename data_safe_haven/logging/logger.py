"""Custom logging functions to interact with Python logging."""

import logging
from datetime import UTC, datetime

from rich.logging import RichHandler

from data_safe_haven.directories import log_dir

from .plain_file_handler import PlainFileHandler


def get_logger() -> logging.Logger:
    return logging.getLogger("data_safe_haven")


def init_logging() -> None:
    # Configure root logger
    # By default logging level is WARNING
    root_logger = logging.getLogger(None)
    root_logger.setLevel(logging.NOTSET)

    # Configure DSH logger
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

    file_handler = PlainFileHandler(
        log_dir() / logfile_name(),
        delay=True,
        encoding="utf8",
        mode="a",
    )
    file_handler.setFormatter(
        logging.Formatter(r"%(asctime)s - %(levelname)s - %(message)s")
    )
    file_handler.setLevel(logging.NOTSET)

    # Add handlers
    logger.addHandler(console_handler)
    logger.console_handler = console_handler  # type: ignore [attr-defined]
    logger.addHandler(file_handler)
    logger.file_handler = file_handler  # type: ignore [attr-defined]

    # Disable unnecessarily verbose external logging
    logging.getLogger("azure.core.pipeline.policies").setLevel(logging.ERROR)
    logging.getLogger("azure.identity._credentials").setLevel(logging.ERROR)
    logging.getLogger("azure.identity._internal").setLevel(logging.ERROR)
    logging.getLogger("azure.mgmt.core.policies").setLevel(logging.ERROR)
    logging.getLogger("urllib3.connectionpool").setLevel(logging.ERROR)


def logfile_name() -> str:
    return f"{datetime.now(UTC).date()}.log"


def set_console_level(level: int | str) -> None:
    get_logger().console_handler.setLevel(level)  # type: ignore [attr-defined]


def show_console_level() -> None:
    get_logger().console_handler._log_render.show_level = True  # type: ignore [attr-defined]
