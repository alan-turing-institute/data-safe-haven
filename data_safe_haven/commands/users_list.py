"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
from typing import Optional

# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.external.api import GraphApi
from data_safe_haven.mixins import LoggingMixin


class UsersListCommand(LoggingMixin, Command):  # type: ignore
    """
    List users for a Data Safe Haven deployment

    list
        {--o|output= : Path to an output log file}
    """

    output: Optional[str]

    def handle(self) -> int:
        shm_name = "UNKNOWN"
        try:
            # Process command line arguments
            self.process_arguments()

            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.output)

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
                default_scopes=["Directory.Read.All", "Group.Read.All"],
            )

            # List users from all sources
            users = UserHandler(config, graph_api)
            users.list()
            return 0
        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not list users for Data Safe Haven '{shm_name}'.\n{str(exc)}".split(
                "\n"
            ):
                self.error(line)
        return 1

    def process_arguments(self) -> None:
        """Load command line arguments into attributes"""
        # Output
        output = self.option("output")
        if not isinstance(output, str) and (output is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{output}' provided for 'output'."
            )
        self.output = output
