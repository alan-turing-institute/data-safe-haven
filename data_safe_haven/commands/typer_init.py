"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
from typing import Annotated, Optional

# Third party imports
import typer

# Local imports
from data_safe_haven.functions import validate_aad_guid
from .initialise_command import InitialiseCommand


def initialise_command(
    admin_group: Annotated[
        Optional[str],
        typer.Option(
            "--admin-group",
            "-a",
            help="The ID of an Azure group containing all administrators.",
            callback=validate_aad_guid,
        ),
    ] = None,
    location: Annotated[
        Optional[str],
        typer.Option(
            "--location",
            "-l",
            help="The Azure location to deploy resources into.",
        ),
    ] = None,
    name: Annotated[
        Optional[str],
        typer.Option(
            "--deployment-name",
            "-d",
            help="The name to give this Data Safe Haven deployment.",
        ),
    ] = None,
    subscription: Annotated[
        Optional[str],
        typer.Option(
            "--subscription",
            "-s",
            help="The name of an Azure subscription to deploy resources into.",
        ),
    ] = None,
) -> None:
    """Initialise a Data Safe Haven deployment"""
    InitialiseCommand()(admin_group, location, name, subscription)
