"""Command-line application for initialising a Data Safe Haven deployment"""
from typing import Annotated, Optional

import typer

from data_safe_haven.backend import Backend
from data_safe_haven.config import BackendSettings
from data_safe_haven.exceptions import DataSafeHavenError
from data_safe_haven.functions import validate_aad_guid


def initialise_command(
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
    """Typer command line entrypoint"""
    try:
        # Load backend settings and update with command line arguments
        settings = BackendSettings()
        settings.update(
            admin_group_id=admin_group,
            location=location,
            name=name,
            subscription_name=subscription,
        )

        # Ensure that the Pulumi backend exists
        backend = Backend()
        backend.create()

        # Load the generated configuration file and upload it to blob storage
        backend.config.upload()

    except DataSafeHavenError as exc:
        msg = f"Could not initialise Data Safe Haven.\n{exc}"
        raise DataSafeHavenError(msg) from exc
