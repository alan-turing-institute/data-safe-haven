from typing import Optional

from clikit.console_application import ConsoleApplication

from .commands import BaseCommand
from .config import ApplicationConfig as ApplicationConfig

class Application(ConsoleApplication):
    def __init__(
        self,
        name: Optional[str],
        version: Optional[str],
        complete: Optional[bool],
        config: Optional[ApplicationConfig] = ...,
    ) -> None: ...
    def add(self, command: BaseCommand) -> Application: ...
