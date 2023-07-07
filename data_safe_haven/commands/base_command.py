# Standard library imports
from abc import ABC, abstractmethod
from typing import Any, Callable

# Third-party imports
import typer

# Local imports
from data_safe_haven.utility import Logger


class IBaseCommand(ABC):
    """Command with entrypoint for use with Typer"""

    @abstractmethod
    def entrypoint(self, *args: Any, **kwargs: Any) -> None:
        """Typer command line entrypoint"""
        pass


class BaseCommand(IBaseCommand):
    """IBaseCommand with logger"""

    def __init__(self):
        """Constructor"""
        self.logger = Logger()


class CommandGroup(typer.Typer):
    """Command group containing subcommands"""

    def subgroup(self, cls: type["CommandGroup"], name: str, help: str) -> None:
        """Register a command group"""
        self.add_typer(cls(), name=name, help=help)

    def subcommand(self, cls: type[BaseCommand], name: str, help: str) -> None:
        """Register a command"""
        self.command(name=name, help=help)(cls().entrypoint)
