"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
import pathlib

# Local imports
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.external.api import GraphApi


class UsersAddCommand:
    """Add users to a deployed Data Safe Haven"""

    def __call__(self, csv_path: pathlib.Path) -> None:
        """Typer command line entrypoint"""
        shm_name = "UNKNOWN"
        try:
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
            users.add(csv_path)
        except DataSafeHavenException as exc:
            raise DataSafeHavenException(
                f"Could not add users to Data Safe Haven '{shm_name}'.\n{str(exc)}"
            ) from exc
