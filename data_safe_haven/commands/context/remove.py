from typing import Annotated

import typer

from data_safe_haven.context import (
    ContextSettings,
)

from .command_group import context_command_group


@context_command_group.command()
def remove(
    key: Annotated[str, typer.Argument(help="Name of the context to remove.")],
) -> None:
    """Removes a context."""
    settings = ContextSettings.from_file()
    settings.remove(key)
    settings.write()
