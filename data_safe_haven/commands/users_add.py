"""Command-line application for initialising a Data Safe Haven deployment"""
# Third party imports
from cleo import Command
from typing import cast

# Local imports
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.external.api import GraphApi
from data_safe_haven.mixins import LoggingMixin


class UsersAddCommand(LoggingMixin, Command):
    """
    Add users to a Data Safe Haven deployment

    add
        {csv : CSV file containing details of users to add.}
        {--o|output= : Path to an output log file}
    """

    def handle(self):
        try:
            environment_name = "UNKNOWN"
            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.option("output"))

            # Use dotfile settings to load the job configuration
            try:
                settings = DotFileSettings()
            except DataSafeHavenException as exc:
                raise DataSafeHavenInputException(
                    f"Unable to load project settings. Please run this command from inside the project directory.\n{str(exc)}"
                ) from exc
            config = Config(settings.name, settings.subscription_name)
            environment_name = config.name

            # Load GraphAPI as this may require user-interaction that is not possible as part of a Pulumi declarative command
            graph_api = GraphApi(
                tenant_id=config.shm.aad_tenant_id,
                default_scopes=["Group.Read.All"],
            )

            # Add users to SHM
            users = UserHandler(config, graph_api)
            users.add(cast(str, self.argument("csv")))
        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not add users to Data Safe Haven '{environment_name}'.\n{str(exc)}".split(
                "\n"
            ):
                self.error(line)
