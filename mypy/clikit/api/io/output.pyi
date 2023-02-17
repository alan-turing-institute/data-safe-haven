from typing import Optional

from clikit.api.formatter import Formatter

from .output_stream import OutputStream

class Output(Formatter):
    def __init__(
        self, stream: OutputStream, formatter: Optional[Formatter] = ...
    ) -> None: ...
