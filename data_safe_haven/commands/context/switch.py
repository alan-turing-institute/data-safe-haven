from typing import Annotated

import typer

from data_safe_haven.context import (
    ContextSettings,
)

from .command_group import context_command_group


@context_command_group.command()
def switch(
    key: Annotated[str, typer.Argument(help="Key of the context to switch to.")]
) -> None:
    """Switch the selected context."""
    settings = ContextSettings.from_file()
    settings.selected = key
    settings.write()
