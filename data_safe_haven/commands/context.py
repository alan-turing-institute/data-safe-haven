"""Command group and entrypoints for managing a DSH context"""

from typing import Annotated, Optional

import typer

from data_safe_haven import console, validators
from data_safe_haven.config import ContextManager
from data_safe_haven.exceptions import DataSafeHavenConfigError
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

    current_context_name = manager.selected
    current_context = manager.context

    console.print(f"Current context: [green]{current_context_name}[/]")
    if current_context is not None:
        console.print(
            f"\tAdmin group name: [blue]{current_context.admin_group_name}[/]",
            f"\tDescription: [blue]{current_context.description}[/]",
            f"\tSubscription name: [blue]{current_context.subscription_name}[/]",
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

    current_context_name = manager.selected
    available = manager.available

    if current_context_name is not None:
        available.remove(current_context_name)
        available = [f"[green]{current_context_name}*[/]", *available]

    console.print("\n".join(available))


@context_command_group.command()
def switch(
    name: Annotated[str, typer.Argument(help="Name of the context to switch to.")]
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
    manager.selected = name
    manager.write()


@context_command_group.command()
def add(
    admin_group_name: Annotated[
        str,
        typer.Option(
            help="Name of a security group that contains all Azure infrastructure admins.",
            callback=validators.typer_entra_group_name,
        ),
    ],
    description: Annotated[
        str,
        typer.Option(
            help="The human-friendly name to give this Data Safe Haven deployment.",
        ),
    ],
    name: Annotated[
        str,
        typer.Option(
            help="A name for this context which consists only of letters, numbers and underscores.",
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
        admin_group_name=admin_group_name,
        description=description,
        name=name,
        subscription_name=subscription_name,
    )
    manager.selected = name
    manager.write()


@context_command_group.command()
def update(
    admin_group_name: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="Name of a security group that contains all Azure infrastructure admins.",
            callback=validators.typer_entra_group_name,
        ),
    ] = None,
    description: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="The human friendly name to give this Data Safe Haven deployment.",
        ),
    ] = None,
    name: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="A name for this context which consists only of letters, numbers and underscores.",
            callback=validators.typer_safe_string,
        ),
    ] = None,
    subscription: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="The name of an Azure subscription to deploy resources into.",
            callback=validators.typer_azure_subscription_name,
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
        admin_group_name=admin_group_name,
        description=description,
        name=name,
        subscription_name=subscription,
    )
    manager.write()


@context_command_group.command()
def remove(
    name: Annotated[str, typer.Argument(help="Name of the context to remove.")],
) -> None:
    """Removes a context from the the context manager."""
    logger = get_logger()
    try:
        manager = ContextManager.from_file()
    except DataSafeHavenConfigError as exc:
        logger.critical("No context configuration file.")
        raise typer.Exit(1) from exc
    manager.remove(name)
    manager.write()
