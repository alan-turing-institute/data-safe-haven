from typing import Optional

from clikit.api.formatter import Formatter, StyleSet

class PlainFormatter(Formatter):
    def __init__(self, style_set: Optional[StyleSet] = None) -> None: ...
