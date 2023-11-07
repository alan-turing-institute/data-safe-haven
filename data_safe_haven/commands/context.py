"""Command group and entrypoints for managing a DSH context"""
from typing import Annotated, Optional

import typer
from rich import print

from data_safe_haven.config import Config, ContextSettings
from data_safe_haven.config.context_settings import Context
from data_safe_haven.config.context_settings import default_config_file_path
from data_safe_haven.context import Context as ContextInfra
from data_safe_haven.functions import validate_aad_guid

context_command_group = typer.Typer()


@context_command_group.command()
def show() -> None:
    """Show information about the selected context."""
    settings = ContextSettings.from_file()

    current_context_key = settings.selected
    current_context = settings.context

    print(f"Current context: [green]{current_context_key}")
    print(f"\tName: {current_context.name}")
    print(f"\tAdmin Group ID: {current_context.admin_group_id}")
    print(f"\tSubscription name: {current_context.subscription_name}")
    print(f"\tLocation: {current_context.location}")


@context_command_group.command()
def available() -> None:
    """Show the available contexts."""
    settings = ContextSettings.from_file()

    current_context_key = settings.selected
    available = settings.available

    available.remove(current_context_key)
    available = [f"[green]{current_context_key}*[/]", *available]

    print("\n".join(available))


@context_command_group.command()
def switch(
    key: Annotated[str, typer.Argument(help="Key of the context to switch to.")]
) -> None:
    """Switch the selected context."""
    settings = ContextSettings.from_file()
    settings.selected = key
    settings.write()


@context_command_group.command()
def add(
    key: Annotated[str, typer.Argument(help="Key of the context to add.")],
    admin_group: Annotated[
        str,
        typer.Option(
            help="The ID of an Azure group containing all administrators.",
            callback=validate_aad_guid,
        ),
    ],
    location: Annotated[
        str,
        typer.Option(
            help="The Azure location to deploy resources into.",
        ),
    ],
    name: Annotated[
        str,
        typer.Option(
            help="The human friendly name to give this Data Safe Haven deployment.",
        ),
    ],
    subscription: Annotated[
        str,
        typer.Option(
            help="The name of an Azure subscription to deploy resources into.",
        ),
    ],
) -> None:
    """Add a new context to the context list."""
    if default_config_file_path().exists():
        settings = ContextSettings.from_file()
        settings.add(
            key=key,
            admin_group_id=admin_group,
            location=location,
            name=name,
            subscription_name=subscription,
        )
    else:
        # Bootstrap context settings file
        settings = ContextSettings(
            selected=key,
            contexts={
                key: Context(
                    admin_group_id=admin_group,
                    location=location,
                    name=name,
                    subscription_name=subscription,
                )
            },
        )
    settings.write()


@context_command_group.command()
def update(
    admin_group: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="The ID of an Azure group containing all administrators.",
            callback=validate_aad_guid,
        ),
    ] = None,
    location: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="The Azure location to deploy resources into.",
        ),
    ] = None,
    name: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="The human friendly name to give this Data Safe Haven deployment.",
        ),
    ] = None,
    subscription: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="The name of an Azure subscription to deploy resources into.",
        ),
    ] = None,
) -> None:
    """Update the selected context settings."""
    settings = ContextSettings.from_file()
    settings.update(
        admin_group_id=admin_group,
        location=location,
        name=name,
        subscription_name=subscription,
    )
    settings.write()


@context_command_group.command()
def remove(
    key: Annotated[str, typer.Argument(help="Name of the context to remove.")],
) -> None:
    """Remove the selected context."""
    settings = ContextSettings.from_file()
    settings.remove(key)
    settings.write()


@context_command_group.command()
def create() -> None:
    """Create Data Safe Haven context infrastructure."""
    config = Config()
    context = ContextInfra(config)
    context.create()
    context.config.upload()


@context_command_group.command()
def teardown() -> None:
    """Tear down Data Safe Haven context infrastructure."""
    config = Config()
    context = ContextInfra(config)
    context.teardown()
