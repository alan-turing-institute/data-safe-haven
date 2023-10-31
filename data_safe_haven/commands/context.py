"""Command group and entrypoints for managing a DSH context"""
from typing import Annotated

import typer
from rich import print

from data_safe_haven.backend import Backend
from data_safe_haven.config import ContextSettings
from data_safe_haven.exceptions import (
    DataSafeHavenError,
    DataSafeHavenInputError,
)
from data_safe_haven.functions import validate_aad_guid

context_command_group = typer.Typer()


@context_command_group.command()
def show() -> None:
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
    settings = ContextSettings.from_file()

    current_context_key = settings.selected
    available = settings.available

    available.remove(current_context_key)
    available = [f"[green]{current_context_key}*[/]"]+available

    print("\n".join(available))


@context_command_group.command()
def switch(
    name: Annotated[str, typer.Argument(help="Name of the context to switch to.")]
) -> None:
    settings = ContextSettings.from_file()
    settings.selected = name
    settings.write()


@context_command_group.command()
def add(
    key: Annotated[
        str,
        typer.Argument(help="Name of the context to add.")
    ],
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
    settings = ContextSettings.from_file()
    settings.add(
        key=key,
        admin_group_id=admin_group,
        location=location,
        name=name,
        subscription_name=subscription,
    )
    settings.write()


@context_command_group.command()
def remove(
    key: Annotated[
        str,
        typer.Argument(help="Name of the context to add.")
    ],
) -> None:
    settings = ContextSettings.from_file()
    settings.remove(key)
    settings.write()


@context_command_group.command()
def create() -> None:
    backend = Backend()  # How does this get the config!?!
    backend.create()

    backend.config.upload()  # What does this do?


@context_command_group.command()
def teardown() -> None:
    """Tear down a Data Safe Haven context"""
    try:
        try:
            backend = Backend()
            backend.teardown()
        except Exception as exc:
            msg = f"Unable to teardown Pulumi backend.\n{exc}"
            raise DataSafeHavenInputError(msg) from exc  # Input error? No input.
    except DataSafeHavenError as exc:
        msg = f"Could not teardown Data Safe Haven backend.\n{exc}"
        raise DataSafeHavenError(msg) from exc
