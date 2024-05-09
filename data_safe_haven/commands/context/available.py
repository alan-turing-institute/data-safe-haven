from rich import print

from data_safe_haven.context import (
    ContextSettings,
)

from .command_group import context_command_group


@context_command_group.command()
def available() -> None:
    """Show the available contexts."""
    settings = ContextSettings.from_file()

    current_context_key = settings.selected
    available = settings.available

    if current_context_key is not None:
        available.remove(current_context_key)
        available = [f"[green]{current_context_key}*[/]", *available]

    print("\n".join(available))
