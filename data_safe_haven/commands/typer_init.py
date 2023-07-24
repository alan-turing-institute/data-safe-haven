"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
from typing import Annotated, Optional

# Third party imports
import typer

from data_safe_haven.commands.initialise_command import InitialiseCommand

# Local imports
from data_safe_haven.functions import validate_aad_guid


def initialise_command(
    admin_group: Annotated[
        str | None,
        typer.Option(
            "--admin-group",
            "-a",
            help="The ID of an Azure group containing all administrators.",
            callback=validate_aad_guid,
        ),
    ] = None,
    location: Annotated[
        str | None,
        typer.Option(
            "--location",
            "-l",
            help="The Azure location to deploy resources into.",
        ),
    ] = None,
    name: Annotated[
        str | None,
        typer.Option(
            "--name",
            "-n",
            help="The name to give this Data Safe Haven deployment.",
        ),
    ] = None,
    subscription: Annotated[
        str | None,
        typer.Option(
            "--subscription",
            "-s",
            help="The name of an Azure subscription to deploy resources into.",
        ),
    ] = None,
) -> None:
    """Initialise a Data Safe Haven deployment"""
    InitialiseCommand()(admin_group, location, name, subscription)
