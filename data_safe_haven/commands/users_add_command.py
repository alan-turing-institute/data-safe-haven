"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
import pathlib
from typing import Optional
from typing_extensions import Annotated

# Third party imports
from cleo import Command
import typer

# Local imports
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.external.api import GraphApi
from data_safe_haven.utility import Logger
from .base_command import BaseCommand


class UsersAddCommand(BaseCommand):  # type: ignore
    """Add users to a deployed Data Safe Haven"""

    def entrypoint(
        self,
        csv: Annotated[
            pathlib.Path,
            typer.Argument(
                help="A CSV file containing details of users to add.",
            ),
        ],
    ) -> None:
        shm_name = "UNKNOWN"
        try:
            # # Process command line arguments
            # self.process_arguments()

            # # Set up logging for anything called by this command
            # self.logger = Logger(self.io.verbosity, self.output)

            # Use dotfile settings to load the job configuration
            try:
                settings = DotFileSettings()
            except DataSafeHavenException as exc:
                raise DataSafeHavenInputException(
                    f"Unable to load project settings. Please run this command from inside the project directory.\n{str(exc)}"
                ) from exc
            config = Config(settings.name, settings.subscription_name)
            shm_name = config.name

            # Load GraphAPI as this may require user-interaction that is not possible as part of a Pulumi declarative command
            graph_api = GraphApi(
                tenant_id=config.shm.aad_tenant_id,
                default_scopes=["Group.Read.All"],
            )

            # Add users to SHM
            users = UserHandler(config, graph_api)
            users.add(csv)
        except DataSafeHavenException as exc:
            raise DataSafeHavenException(
                f"Could not add users to Data Safe Haven '{shm_name}'.\n{str(exc)}"
            ) from exc
