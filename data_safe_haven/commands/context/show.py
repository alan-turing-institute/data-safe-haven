import typer
from rich import print

from data_safe_haven.context import (
    ContextSettings,
)
from data_safe_haven.exceptions import DataSafeHavenConfigError

from .command_group import context_command_group


@context_command_group.command()
def show() -> None:
    """Show information about the selected context."""
    try:
        settings = ContextSettings.from_file()
    except DataSafeHavenConfigError as exc:
        print("No context configuration file.")
        raise typer.Exit(code=1) from exc

    current_context_key = settings.selected
    current_context = settings.context

    print(f"Current context: [green]{current_context_key}")
    if current_context is not None:
        print(f"\tName: {current_context.name}")
        print(f"\tAdmin Group ID: {current_context.admin_group_id}")
        print(f"\tSubscription name: {current_context.subscription_name}")
        print(f"\tLocation: {current_context.location}")
