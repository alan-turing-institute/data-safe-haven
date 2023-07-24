"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
import pathlib

# Local imports
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config
from data_safe_haven.exceptions import (
    DataSafeHavenError,
)
from data_safe_haven.external import GraphApi


class UsersAddCommand:
    """Add users to a deployed Data Safe Haven"""

    def __call__(self, csv_path: pathlib.Path) -> None:
        """Typer command line entrypoint"""
        shm_name = "UNKNOWN"
        try:
            # Load config file
            config = Config()
            shm_name = config.name

            # Load GraphAPI as this may require user-interaction that is not
            # possible as part of a Pulumi declarative command
            graph_api = GraphApi(
                tenant_id=config.shm.aad_tenant_id,
                default_scopes=["Group.Read.All"],
            )

            # Add users to SHM
            users = UserHandler(config, graph_api)
            users.add(csv_path)
        except DataSafeHavenError as exc:
            msg = f"Could not add users to Data Safe Haven '{shm_name}'.\n{exc!s}"
            raise DataSafeHavenError(msg) from exc
