from typing import Any

from clikit.io import ConsoleIO as BaseConsoleIO

from .io_mixin import IOMixin

class ConsoleIO(IOMixin, BaseConsoleIO):
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
