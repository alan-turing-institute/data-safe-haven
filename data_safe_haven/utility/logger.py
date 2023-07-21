"""Standalone logging class implemented as a singleton"""
import io
import logging
from typing import Any, ClassVar, Optional

from rich.console import Console
from rich.highlighter import RegexHighlighter
from rich.logging import RichHandler
from rich.prompt import Confirm, Prompt
from rich.table import Table
from rich.text import Text

from .singleton import Singleton
from .types import PathType


class LoggingHandlerPlainFile(logging.FileHandler):
    """
    Logging handler that cleans messages before sending them to a log file.
    """

    def __init__(
        self, fmt: str, datefmt: str, filename: str, *args: Any, **kwargs: Any
    ):
        """Constructor"""
        super().__init__(*args, **kwargs, filename=filename)
        self.setFormatter(logging.Formatter(self.strip_formatting(fmt), datefmt))

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


class LoggingHandlerRichConsole(RichHandler):
    """
    Logging handler that uses Rich.
    """

    def __init__(self, fmt: str, datefmt: str, *args: Any, **kwargs: Any):
        super().__init__(
            *args,
            highlighter=LogLevelHighlighter(),
            markup=True,
            omit_repeated_times=False,
            rich_tracebacks=True,
            show_level=False,
            show_time=False,
            tracebacks_show_locals=True,
            **kwargs,
        )
        self.setFormatter(logging.Formatter(fmt, datefmt))


class LogLevelHighlighter(RegexHighlighter):
    """
    Highlighter that looks for [level-name] and applies default formatting.
    """

    base_style = "logging.level."
    highlights: ClassVar[list[str]] = [
        r"(?P<critical>\[CRITICAL\])",
        r"(?P<debug>\[   DEBUG\])",
        r"(?P<error>\[   ERROR\])",
        r"(?P<info>\[    INFO\])",
        r"(?P<warning>\[ WARNING\])",
    ]


class RichStringAdaptor:
    """
    A wrapper to convert Rich objects into strings.
    """

    def __init__(self, *, coloured: bool):
        """Constructor"""
        self.string_io = io.StringIO()
        self.console = Console(file=self.string_io, force_terminal=coloured)

    def to_string(self, *renderables: Any) -> str:
        """Convert Rich renderables into a string"""
        self.console.print(*renderables)
        return self.string_io.getvalue()


class LoggingSingleton(logging.Logger, metaclass=Singleton):
    """
    Logging singleton that can be used by anything needing logging
    """

    date_fmt = r"%Y-%m-%d %H:%M:%S"
    rich_format = r"[log.time]%(asctime)s[/] [%(levelname)8s] %(message)s"
    # Due to https://bugs.python.org/issue45857 we must use `Optional`
    _instance: Optional["LoggingSingleton"] = None

    def __init__(self):
        super().__init__(name="data_safe_haven", level=logging.INFO)
        # Initialise console handler
        self.addHandler(LoggingHandlerRichConsole(self.rich_format, self.date_fmt))
        # Disable unnecessarily verbose external logging
        logging.getLogger("azure.core.pipeline.policies").setLevel(logging.ERROR)
        logging.getLogger("azure.identity._credentials").setLevel(logging.ERROR)
        logging.getLogger("azure.identity._internal").setLevel(logging.ERROR)
        logging.getLogger("azure.mgmt.core.policies").setLevel(logging.ERROR)
        logging.getLogger("urllib3.connectionpool").setLevel(logging.ERROR)

    def log_file(self, file_path: PathType) -> None:
        """Set a log file handler"""
        file_handler = LoggingHandlerPlainFile(
            self.rich_format, self.date_fmt, str(file_path)
        )
        for h in self.handlers:
            if isinstance(h, LoggingHandlerPlainFile):
                self.removeHandler(h)
        self.addHandler(file_handler)

    def verbosity(self, verbosity: int) -> None:
        """Set verbosity"""
        self.setLevel(
            max(logging.INFO - 10 * (verbosity if verbosity else 0), logging.NOTSET)
        )

    def format_msg(self, message: str, level: int = logging.INFO) -> str:
        """Format a message using rich handler"""
        for handler in self.handlers:
            if isinstance(handler, RichHandler):
                fn, lno, func, sinfo = self.findCaller(stack_info=False, stacklevel=1)
                return handler.format(
                    self.makeRecord(
                        name=self.name,
                        level=level,
                        fn=fn,
                        lno=lno,
                        msg=message,
                        args={},
                        exc_info=None,
                        func=func,
                        sinfo=sinfo,
                    )
                )
        return message

    def style(self, message: str) -> str:
        """Apply logging style to a string"""
        markup = self.format_msg(message)
        return RichStringAdaptor(coloured=True).to_string(markup)

    # Loggable wrappers for confirm/ask/choice
    def confirm(self, message: str, *, default_to_yes: bool) -> bool:
        formatted = self.format_msg(message, logging.INFO)
        return Confirm.ask(formatted, default=default_to_yes)

    def ask(self, message: str, default: str | None = None) -> str:
        formatted = self.format_msg(message, logging.INFO)
        if default:
            return Prompt.ask(formatted, default=default)
        return Prompt.ask(formatted)

    def choose(
        self,
        message: str,
        choices: list[str] | None = None,
        default: str | None = None,
    ) -> str:
        formatted = self.format_msg(message, logging.INFO)
        if default:
            return Prompt.ask(formatted, choices=choices, default=default)
        return Prompt.ask(formatted, choices=choices)

    # Apply a level to non-leveled messages
    def parse(self, message: str) -> None:
        tokens = message.split(":")
        level, remainder = tokens[0], ":".join(tokens[1:]).strip()
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

    # Create a table
    def tabulate(
        self, header: list[str] | None = None, rows: list[list[str]] | None = None
    ) -> list[str]:
        table = Table()
        if header:
            for item in header:
                table.add_column(item)
        if rows:
            for row in rows:
                table.add_row(*row)
        adaptor = RichStringAdaptor(coloured=True)
        return [line.strip() for line in adaptor.to_string(table).split("\n")]
