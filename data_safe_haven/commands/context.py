"""Command group and entrypoints for managing a DSH context"""

from typing import Annotated, Optional

import typer

from data_safe_haven import console, validators
from data_safe_haven.config import ContextManager
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
)
from data_safe_haven.logging import get_logger

context_command_group = typer.Typer()


@context_command_group.command()
def show() -> None:
    """Show information about the currently selected context."""
    logger = get_logger()
    try:
        manager = ContextManager.from_file()
    except DataSafeHavenConfigError as exc:
        logger.critical(
            "No context configuration file. Use `dsh context add` to create one."
        )
        raise typer.Exit(code=1) from exc

    current_context_key = manager.selected
    current_context = manager.context

    console.print(f"Current context: [green]{current_context_key}")
    if current_context is not None:
        console.print(
            f"\tName: {current_context.name}",
            f"\tSubscription name: {current_context.subscription_name}",
            sep="\n",
        )


@context_command_group.command()
def available() -> None:
    """Show the available contexts."""
    logger = get_logger()
    try:
        manager = ContextManager.from_file()
    except DataSafeHavenConfigError as exc:
        logger.critical(
            "No context configuration file. Use `dsh context add` to create one."
        )
        raise typer.Exit(code=1) from exc

    current_context_key = manager.selected
    available = manager.available

    if current_context_key is not None:
        available.remove(current_context_key)
        available = [f"[green]{current_context_key}*[/]", *available]

    console.print("\n".join(available))


@context_command_group.command()
def switch(
    key: Annotated[str, typer.Argument(help="Key of the context to switch to.")]
) -> None:
    """Switch the currently selected context."""
    logger = get_logger()
    try:
        manager = ContextManager.from_file()
    except DataSafeHavenConfigError as exc:
        logger.critical(
            "No context configuration file. Use `dsh context add` to create one."
        )
        raise typer.Exit(code=1) from exc
    manager.selected = key
    manager.write()


@context_command_group.command()
def add(
    name: Annotated[
        str,
        typer.Option(
            help="The human friendly name to give this Data Safe Haven deployment.",
        ),
    ],
    subscription_name: Annotated[
        str,
        typer.Option(
            help="The name of an Azure subscription to deploy resources into.",
            callback=validators.typer_azure_subscription_name,
        ),
    ],
) -> None:
    """Add a new context to the context manager."""
    # Create a new context settings file if none exists
    if ContextManager.default_config_file_path().exists():
        manager = ContextManager.from_file()
    else:
        manager = ContextManager(contexts={}, selected=None)
    # Add the context to the file and write it
    manager.add(
        name=name,
        subscription_name=subscription_name,
    )
    manager.write()


@context_command_group.command()
def update(
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
    """Update the currently selected context."""
    logger = get_logger()
    try:
        manager = ContextManager.from_file()
    except DataSafeHavenConfigError as exc:
        logger.critical(
            "No context configuration file. Use `dsh context add` to create one."
        )
        raise typer.Exit(1) from exc

    manager.update(
        name=name,
        subscription_name=subscription,
    )
    manager.write()


@context_command_group.command()
def remove(
    key: Annotated[str, typer.Argument(help="Name of the context to remove.")],
) -> None:
    """Removes a context from the the context manager."""
    logger = get_logger()
    try:
        manager = ContextManager.from_file()
    except DataSafeHavenConfigError as exc:
        logger.critical("No context configuration file.")
        raise typer.Exit(1) from exc
    manager.remove(key)
    manager.write()
