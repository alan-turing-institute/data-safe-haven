"""Mixin class for anything needing logging"""
# Standard library imports
import datetime
import io
import logging
import re
from typing import Any, Dict, List, Optional

# Third party imports
from cleo.io import ConsoleIO
from clikit.api.io import Output, flags
from clikit.formatter import AnsiFormatter, PlainFormatter
from clikit.io.output_stream import StreamOutputStream
from clikit.ui.components import Table


def strip_formatting(input_string: str) -> str:
    first_pass = PlainFormatter().remove_format(input_string)
    return re.sub("<[^>]*>", "", first_pass)


class CleoStringIO(ConsoleIO):
    """
    A wrapper to coerce Cleo IO into a StringIO stream.
    """

    def __init__(self, *args: Any, **kwargs: Any):
        self.stdout = io.StringIO()
        kwargs["output"] = Output(StreamOutputStream(self.stdout), AnsiFormatter())
        super().__init__(*args, **kwargs)


class LoggingFilterColouredLevel(logging.Filter):
    STYLES = {
        "DEBUG": "fg=light_cyan",
        "INFO": "fg=white",
        "WARNING": "fg=yellow",
        "ERROR": "fg=light_red",
        "CRITICAL": "bg=red",
    }

    def filter(self, record: logging.LogRecord) -> bool:
        record.style = LoggingFilterColouredLevel.STYLES[record.levelname]
        return True


class LoggingHandlerClikit(logging.Handler):
    """Logging handler that redirects all messages to clikit io object."""

    def __init__(
        self,
        level: int = logging.NOTSET,
        fmt: Optional[str] = None,
        datefmt: Optional[str] = None,
    ):
        super().__init__(level=level)
        self.io = ConsoleIO()
        if fmt:
            if datefmt:
                self.setFormatter(logging.Formatter(fmt, datefmt))
            else:
                self.setFormatter(logging.Formatter(fmt))

    def emit(self, record: logging.LogRecord) -> None:
        msg = self.format(record)
        if hasattr(record, "tag") and record.tag == "no_console":
            return
        # Send error and above to stderr
        if record.levelno >= logging.ERROR:
            # If overwrite is allowed then call the appropriate function
            if hasattr(record, "action"):
                if record.action == "no_newline":
                    self.io.error(msg)
                    self.io._last_message_err = msg  # workaround for a bug in clikit
                elif record.action == "overwrite":
                    self.io.overwrite_error(msg)
                    self.io.error_line("")  # needed to correctly insert a newline
            # Otherwise use the default function
            else:
                self.io.error_line(msg, flags.NORMAL)
        # Send other messages to stdout
        else:
            # If overwrite is allowed then call the appropriate function
            if hasattr(record, "action"):
                if record.action == "no_newline":
                    self.io.write(msg)
                elif record.action == "overwrite":
                    self.io.overwrite(msg)
                    self.io.write_line("")  # needed to correctly insert a newline
            # Otherwise use the default function
            else:
                self.io.write_line(msg, flags.NORMAL)


class LoggingHandlerPlainFile(logging.FileHandler):
    """Logging handler that cleans messages before sending them to a log file."""

    def emit(self, record: logging.LogRecord) -> None:
        # Strip formatting from the record before logging it
        record.msg = strip_formatting(record.msg)
        super().emit(record)


class LoggingMixin:
    """Mixin class for anything needing logging"""

    date_fmt = r"%Y-%m-%d %H:%M:%S"
    coloured_fmt = "<fg=blue>%(asctime)s</> <%(style)s>[%(levelname)8s]</> %(message)s"
    is_setup = False

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self.logger = logging.getLogger("data_safe_haven")
        self.console = LoggingHandlerClikit(
            fmt=self.coloured_fmt, datefmt=self.date_fmt
        )
        self.console.addFilter(LoggingFilterColouredLevel())

    @property
    def prefix(self) -> str:
        return f"<fg=blue>[{datetime.datetime.now().isoformat(timespec='seconds')}]</>"

    @staticmethod
    def extra_args(no_newline: bool = False, overwrite: bool = False) -> Dict[str, str]:
        extra = {}
        if no_newline:
            extra["action"] = "no_newline"
        if overwrite:
            extra["action"] = "overwrite"
        return extra

    def format_msg(self, message: str, level: int = logging.INFO) -> str:
        record = self.logger.makeRecord(
            name=self.logger.name,
            level=level,
            fn="",
            lno=0,
            msg=message,
            args={},
            exc_info=None,
        )
        record.style = LoggingFilterColouredLevel.STYLES[record.levelname]
        return self.console.format(record)

    def initialise_logging(self, verbosity: int, log_file: Optional[str]) -> None:
        """Initialise logging handlers and formatters."""
        if not self.is_setup:
            # Setup handlers
            handlers: List[logging.Handler] = [self.console]
            if log_file:
                handlers += [LoggingHandlerPlainFile(log_file)]
            # Set basic logging config
            logging.basicConfig(
                datefmt=self.date_fmt,
                format=strip_formatting(self.coloured_fmt),
                handlers=handlers,
                level=max(logging.INFO - 10 * verbosity, 0),
            )
            # Disable unnecessarily verbose Azure logging
            logging.getLogger("azure.core.pipeline.policies").setLevel(logging.ERROR)
            logging.getLogger("azure.identity._credentials").setLevel(logging.ERROR)
            logging.getLogger("azure.identity._internal").setLevel(logging.ERROR)
            logging.getLogger("azure.mgmt.core.policies").setLevel(logging.ERROR)

    # Pass log levels through to the logger
    def critical(
        self, message: str, no_newline: bool = False, overwrite: bool = False
    ) -> None:
        return self.logger.critical(
            message, extra=self.extra_args(no_newline, overwrite)
        )

    def error(
        self, message: str, no_newline: bool = False, overwrite: bool = False
    ) -> None:
        return self.logger.error(message, extra=self.extra_args(no_newline, overwrite))

    def warning(
        self, message: str, no_newline: bool = False, overwrite: bool = False
    ) -> None:
        return self.logger.warning(
            message, extra=self.extra_args(no_newline, overwrite)
        )

    def info(
        self, message: str, no_newline: bool = False, overwrite: bool = False
    ) -> None:
        return self.logger.info(message, extra=self.extra_args(no_newline, overwrite))

    def debug(
        self, message: str, no_newline: bool = False, overwrite: bool = False
    ) -> None:
        return self.logger.debug(message, extra=self.extra_args(no_newline, overwrite))

    # Loggable wrappers for confirm/ask/choice
    def log_confirm(self, message: str, *args: Any, **kwargs: Any) -> str:
        formatted = self.format_msg(message, logging.INFO)
        self.logger.info(message, extra={"tag": "no_console"})
        return self.console.io.confirm(formatted, *args, **kwargs)

    def log_ask(self, message: str, *args: Any, **kwargs: Any) -> str:
        formatted = self.format_msg(message, logging.INFO)
        self.logger.info(message, extra={"tag": "no_console"})
        return self.console.io.ask(formatted, *args, **kwargs)

    def log_choose(self, message: str, *args: Any, **kwargs: Any) -> str:
        formatted = self.format_msg(message, logging.INFO)
        self.logger.info(message, extra={"tag": "no_console"})
        return self.console.io.choice(formatted, *args, **kwargs)

    def parse_as_log(
        self, message: str, no_newline: bool = False, overwrite: bool = False
    ) -> None:
        tokens = message.split(":")
        level, remainder = tokens[0], ":".join(tokens[1:]).strip()
        if level == "CRITICAL":
            return self.critical(remainder, no_newline, overwrite)
        elif level == "ERROR":
            return self.error(remainder, no_newline, overwrite)
        elif level == "WARNING":
            return self.warning(remainder, no_newline, overwrite)
        elif level == "INFO":
            return self.info(remainder, no_newline, overwrite)
        elif level == "DEBUG":
            return self.debug(remainder, no_newline, overwrite)
        else:
            return self.info(message.strip(), no_newline, overwrite)

    # Create a table
    def tabulate(
        self, header: Optional[List[str]] = None, rows: Optional[List[List[str]]] = None
    ) -> List[str]:
        table = Table()
        if header:
            table.set_header_row(header)
        if rows:
            table.set_rows(rows)
        string_io = CleoStringIO()
        table.render(string_io)
        string_io.stdout.seek(0)
        return [line.strip() for line in string_io.stdout.readlines()]
