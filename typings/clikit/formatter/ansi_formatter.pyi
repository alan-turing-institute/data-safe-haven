from typing import Optional

from _typeshed import Incomplete
from clikit.api.formatter import Formatter, StyleSet

class AnsiFormatter(Formatter):
    def __init__(
        self, style_set: Optional[StyleSet] = None, forced: Optional[bool] = False
    ) -> None: ...
