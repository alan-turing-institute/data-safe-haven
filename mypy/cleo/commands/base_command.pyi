from _typeshed import Incomplete
from cleo.io import ConsoleIO as ConsoleIO
from clikit.api.args import Args as Args
from clikit.api.command import Command as CliKitCommand
from clikit.api.config.command_config import CommandConfig
from typing import Optional

class CommandError(Exception): ...

class BaseCommand:
    name: Incomplete
    description: Incomplete
    help: Incomplete
    arguments: Incomplete
    options: Incomplete
    aliases: Incomplete
    enabled: bool
    hidden: bool
    commands: Incomplete
    def __init__(self) -> None: ...
    @property
    def config(self) -> CommandConfig: ...
    @property
    def application(self): ...
    def handle(
        self, args: Args, io: ConsoleIO, command: CliKitCommand
    ) -> Optional[int]: ...
    def set_application(self, application) -> None: ...
    def add_sub_command(self, command: BaseCommand) -> None: ...
    def default(self, default: bool = ...) -> BaseCommand: ...
    def anonymous(self) -> BaseCommand: ...
