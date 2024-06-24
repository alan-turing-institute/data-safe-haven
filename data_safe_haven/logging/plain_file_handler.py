"""Custom logging handler to interact with Python logging."""

import logging
from typing import Any

from rich.text import Text


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

    @staticmethod
    def convert_text(text: Text) -> str:
        """Convert a rich.text.Text object to a string"""
        return str(text)

    def emit(self, record: logging.LogRecord) -> None:
        """Emit a record without formatting"""
        if isinstance(record.msg, Text):
            record.msg = self.convert_text(record.msg)
        record.msg = self.strip_formatting(record.msg)
        super().emit(record)
