from typing import List, Optional

from clikit.api.io import IO
from clikit.ui import Component
from clikit.ui.style import TableStyle

class Table(Component):
    """
    A table of rows and columns.
    """

    def __init__(self, style: Optional[TableStyle] = None) -> None: ...
    def set_header_row(self, row: List[str]) -> Table: ...
    def set_rows(self, rows: List[List[str]]) -> Table: ...
    def render(self, io: IO, indentation: Optional[int] = None) -> None: ...
