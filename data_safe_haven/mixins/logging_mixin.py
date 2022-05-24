"""Mixin class for anything needing logging"""
# Standard library imports
import datetime
import io
import logging
import re

# Third party imports
from cleo.io import ConsoleIO
from clikit.api.io import flags, Output
from clikit.formatter import AnsiFormatter, PlainFormatter
from clikit.io.output_stream import StreamOutputStream
from clikit.ui.components import Table


def strip_formatting(input_string):
    first_pass = PlainFormatter().remove_format(input_string)
    return re.sub("<[^>]*>", "", first_pass)


class CleoStringIO(ConsoleIO):
    """
    A wrapper to coerce Cleo IO into a StringIO stream.
    """

    def __init__(self, *args, **kwargs):
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

    def filter(self, record):
        record.style = LoggingFilterColouredLevel.STYLES[record.levelname]
        return True


class LoggingHandlerClikit(logging.Handler):
    """Logging handler that redirects all messages to clikit io object."""

    def __init__(self, level=logging.NOTSET, fmt=None, datefmt=None):
        super().__init__(level=level)
        self.io = ConsoleIO()
        if fmt:
            if datefmt:
                self.setFormatter(logging.Formatter(fmt, datefmt))
            else:
                self.setFormatter(logging.Formatter(fmt))

    def emit(self, record: logging.LogRecord):
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

    def emit(self, record: logging.LogRecord):
        # Strip formatting from the record before logging it
        record.msg = strip_formatting(record.msg)
        super().emit(record)


class LoggingMixin:
    """Mixin class for anything needing logging"""

    date_fmt = r"%Y-%m-%d %H:%M:%S"
    coloured_fmt = "<fg=blue>%(asctime)s</> <%(style)s>[%(levelname)-8s]</> %(message)s"
    is_setup = False

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.logger = logging.getLogger("data_safe_haven")
        self.console = LoggingHandlerClikit(
            fmt=self.coloured_fmt, datefmt=self.date_fmt
        )
        self.console.addFilter(LoggingFilterColouredLevel())

    @property
    def prefix(self):
        return f"<fg=blue>[{datetime.datetime.now().isoformat(timespec='seconds')}]</>"

    @staticmethod
    def extra_args(no_newline=False, overwrite=False):
        extra = {}
        if no_newline:
            extra["action"] = "no_newline"
        if overwrite:
            extra["action"] = "overwrite"
        return extra

    def format_msg(self, message, level=logging.INFO):
        record = self.logger.makeRecord(
            msg=message,
            level=level,
            name=self.logger.name,
            fn="",
            lno=0,
            args={},
            exc_info=None,
        )
        record.style = LoggingFilterColouredLevel.STYLES[record.levelname]
        return self.console.format(record)

    def initialise_logging(self, verbosity, log_file):
        """Initialise logging handlers and formatters."""
        if not self.is_setup:
            # Setup handlers
            handlers = [self.console]
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
            logging.getLogger("azure.identity._credentials").setLevel(logging.ERROR)
            logging.getLogger("azure.identity._internal").setLevel(logging.ERROR)
            logging.getLogger("azure.core.pipeline.policies").setLevel(logging.ERROR)

    # Pass log levels through to the logger
    def critical(self, message, no_newline=False, overwrite=False):
        self.logger.critical(message, extra=self.extra_args(no_newline, overwrite))

    def error(self, message, no_newline=False, overwrite=False):
        self.logger.error(message, extra=self.extra_args(no_newline, overwrite))

    def warning(self, message, no_newline=False, overwrite=False):
        self.logger.warning(message, extra=self.extra_args(no_newline, overwrite))

    def info(self, message, no_newline=False, overwrite=False):
        self.logger.info(message, extra=self.extra_args(no_newline, overwrite))

    def debug(self, message, no_newline=False, overwrite=False):
        self.logger.debug(message, extra=self.extra_args(no_newline, overwrite))

    # Loggable wrappers for confirm/ask/choice
    def log_confirm(self, message, *args, **kwargs):
        formatted = self.format_msg(message, logging.INFO)
        self.logger.info(message, extra={"tag": "no_console"})
        return self.console.io.confirm(formatted, *args, **kwargs)

    def log_ask(self, message, *args, **kwargs):
        formatted = self.format_msg(message, logging.INFO)
        self.logger.info(message, extra={"tag": "no_console"})
        return self.console.io.ask(formatted, *args, **kwargs)

    def log_choose(self, message, *args, **kwargs):
        formatted = self.format_msg(message, logging.INFO)
        self.logger.info(message, extra={"tag": "no_console"})
        return self.console.io.choice(formatted, *args, **kwargs)

    def tabulate(self, header=None, rows=None):
        table = Table()
        if header:
            table.set_header_row(header)
        if rows:
            table.set_rows(rows)
        string_io = CleoStringIO()
        table.render(string_io)
        string_io.stdout.seek(0)
        return [line.strip() for line in string_io.stdout.readlines()]
