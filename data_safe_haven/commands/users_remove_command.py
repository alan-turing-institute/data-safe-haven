"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
from typing import List
from typing_extensions import Annotated

# Third party imports
import typer

# Local imports
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.external import GraphApi
from .base_command import BaseCommand


class UsersRemoveCommand(BaseCommand):
    """Remove existing users from a deployed Data Safe Haven"""

    def entrypoint(
        self,
        usernames: Annotated[
            List[str],
            typer.Argument(
                help="Username of a user to remove from this Data Safe Haven. [*may be specified several times*]",
            ),
        ],
    ) -> None:
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

            # Remove users from SHM
            if usernames:
                users = UserHandler(config, graph_api)
                users.remove(usernames)
        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not remove users from Data Safe Haven '{shm_name}'.\n{str(exc)}".split(
                "\n"
            ):
                self.logger.error(line)
