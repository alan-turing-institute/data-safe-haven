from typing import Optional, Tuple
from clikit.api.args.raw_args import RawArgs
from clikit.api.io import InputStream, OutputStream
from clikit.console_application import ConsoleApplication
from .commands import BaseCommand as BaseCommand
from .commands.completions_command import CompletionsCommand as CompletionsCommand
from .config import ApplicationConfig as ApplicationConfig

class Application(ConsoleApplication):
    def __init__(
        self,
        name: str = ...,
        version: str = ...,
        complete: bool = ...,
        config: Optional[ApplicationConfig] = ...,
    ) -> None: ...
    def add_commands(self, *commands: Tuple[BaseCommand]) -> None: ...
    def add(self, command: BaseCommand) -> Application: ...
    def find(self, name: str) -> BaseCommand: ...
    def run(
        self,
        args: Optional[RawArgs] = None,
        input_stream: Optional[InputStream] = None,
        output_stream: Optional[OutputStream] = None,
        error_stream: Optional[OutputStream] = None,
    ) -> int: ...
