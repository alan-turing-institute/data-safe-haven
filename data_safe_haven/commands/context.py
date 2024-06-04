"""Command group and entrypoints for managing a DSH context"""

from typing import Annotated, Optional

import typer
from rich import print

from data_safe_haven import validators
from data_safe_haven.context import (
    Context,
    ContextSettings,
)
from data_safe_haven.context_infrastructure import ContextInfrastructure
from data_safe_haven.exceptions import (
    DataSafeHavenAzureAPIAuthenticationError,
    DataSafeHavenConfigError,
)

context_command_group = typer.Typer()


@context_command_group.command()
def show() -> None:
    """Show information about the selected context."""
    try:
        settings = ContextSettings.from_file()
    except DataSafeHavenConfigError:
        print("No context configuration file. Use `dsh context add` to create one.")
        raise typer.Exit(code=1) from None

    current_context_key = settings.selected
    current_context = settings.context

    print(f"Current context: [green]{current_context_key}")
    if current_context is not None:
        print(f"\tName: {current_context.name}")
        print(f"\tAdmin Group ID: {current_context.admin_group_id}")
        print(f"\tSubscription name: {current_context.subscription_name}")
        print(f"\tLocation: {current_context.location}")


@context_command_group.command()
def available() -> None:
    """Show the available contexts."""
    try:
        settings = ContextSettings.from_file()
    except DataSafeHavenConfigError as exc:
        print("No context configuration file. Use `dsh context add` to create one.")
        raise typer.Exit(code=1) from exc

    current_context_key = settings.selected
    available = settings.available

    if current_context_key is not None:
        available.remove(current_context_key)
        available = [f"[green]{current_context_key}*[/]", *available]

    print("\n".join(available))


@context_command_group.command()
def switch(
    key: Annotated[str, typer.Argument(help="Key of the context to switch to.")]
) -> None:
    """Switch the selected context."""
    try:
        settings = ContextSettings.from_file()
    except DataSafeHavenConfigError:
        print("No context configuration file. Use `dsh context add` to create one.")
        raise typer.Exit(code=1) from None
    settings.selected = key
    settings.write()


@context_command_group.command()
def add(
    key: Annotated[str, typer.Argument(help="Key of the context to add.")],
    admin_group: Annotated[
        str,
        typer.Option(
            help="The ID of an Azure group containing all administrators.",
            callback=validators.typer_aad_guid,
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
    subscription_name: Annotated[
        str,
        typer.Option(
            help="The name of an Azure subscription to deploy resources into.",
            callback=validators.typer_azure_subscription_name,
        ),
    ],
) -> None:
    """Add a new context to the context list."""
    if ContextSettings.default_config_file_path().exists():
        settings = ContextSettings.from_file()
        settings.add(
            key=key,
            admin_group_id=admin_group,
            location=location,
            name=name,
            subscription_name=subscription_name,
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
                    subscription_name=subscription_name,
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
            callback=validators.typer_aad_guid,
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
    try:
        settings = ContextSettings.from_file()
    except DataSafeHavenConfigError:
        print("No context configuration file. Use `dsh context add` to create one.")
        raise typer.Exit(code=1) from None

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
    """Removes a context."""
    try:
        settings = ContextSettings.from_file()
    except DataSafeHavenConfigError:
        print("No context configuration file.")
        raise typer.Exit(code=1) from None
    settings.remove(key)
    settings.write()


@context_command_group.command()
def create() -> None:
    """Create Data Safe Haven context infrastructure."""
    try:
        context = ContextSettings.from_file().assert_context()
    except DataSafeHavenConfigError as exc:
        if exc.args[0] == "No context selected":
            print("No context selected. Use `dsh context switch` to select one.")
        else:
            print(
                "No context configuration file. Use `dsh context add` before creating infrastructure."
            )
        raise typer.Exit(code=1) from None

    context_infra = ContextInfrastructure(context)
    try:
        context_infra.create()
    except DataSafeHavenAzureAPIAuthenticationError:
        print(
            "Failed to authenticate with the Azure API. You may not be logged into the Azure CLI, or your login may have expired. Try running `az login`."
        )
        raise typer.Exit(1) from None


@context_command_group.command()
def teardown() -> None:
    """Tear down Data Safe Haven context infrastructure."""
    try:
        context = ContextSettings.from_file().assert_context()
    except DataSafeHavenConfigError as exc:
        if exc.args[0] == "No context selected":
            print("No context selected. Use `dsh context switch` to select one.")
        else:
            print(
                "No context configuration file. Use `dsh context add` before creating infrastructure."
            )
        raise typer.Exit(code=1) from None

    context_infra = ContextInfrastructure(context)

    try:
        context_infra.teardown()
    except DataSafeHavenAzureAPIAuthenticationError as exc:
        print(
            "Failed to authenticate with the Azure API. You may not be logged into the Azure CLI, or your login may have expired. Try running `az login`."
        )
        raise typer.Exit(1) from exc
