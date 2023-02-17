from typing import Type

from cleo.io import ConsoleIO
from clikit.config import DefaultApplicationConfig

class ApplicationConfig(DefaultApplicationConfig):
    def configure(self) -> None: ...
    @property
    def io_class(self) -> Type[ConsoleIO]: ...
