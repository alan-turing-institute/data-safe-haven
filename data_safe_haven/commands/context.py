"""Command group and entrypoints for managing a DSH context"""
from typing import Annotated, Optional

import typer

from data_safe_haven.backend import Backend
from data_safe_haven.config import BackendSettings
from data_safe_haven.exceptions import (
    DataSafeHavenError,
    DataSafeHavenInputError,
)
from data_safe_haven.functions import validate_aad_guid

context_command_group = typer.Typer()


@context_command_group.command()
def add(
    admin_group: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            "--admin-group",
            "-a",
            help="The ID of an Azure group containing all administrators.",
            callback=validate_aad_guid,
        ),
    ] = None,
    location: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            "--location",
            "-l",
            help="The Azure location to deploy resources into.",
        ),
    ] = None,
    name: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            "--name",
            "-n",
            help="The name to give this Data Safe Haven deployment.",
        ),
    ] = None,
    subscription: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            "--subscription",
            "-s",
            help="The name of an Azure subscription to deploy resources into.",
        ),
    ] = None,
) -> None:
    settings = BackendSettings()
    settings.add(
        admin_group_id=admin_group,
        location=location,
        name=name,
        subscription_name=subscription,
    )


@context_command_group.command()
def remove() -> None:
    pass


@context_command_group.command()
def show() -> None:
    settings = BackendSettings()
    settings.summarise()


@context_command_group.command()
def switch(
    name: Annotated[str, typer.Argument(help="Name of the context to switch to.")]
) -> None:
    settings = BackendSettings()
    settings.switch(name)


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
