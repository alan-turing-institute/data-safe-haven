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


class UsersAddCommand(LoggingMixin, Command):  # type: ignore
    """
    Add users to a Data Safe Haven deployment

    add
        {csv : CSV file containing details of users to add.}
        {--o|output= : Path to an output log file}
    """

    csv_path: Optional[str]
    output: Optional[str]

    def handle(self) -> int:
        environment_name = "UNKNOWN"
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
            environment_name = config.name

            # Load GraphAPI as this may require user-interaction that is not possible as part of a Pulumi declarative command
            graph_api = GraphApi(
                tenant_id=config.shm.aad_tenant_id,
                default_scopes=["Group.Read.All"],
            )

            # Add users to SHM
            users = UserHandler(config, graph_api)
            if not isinstance(self.csv_path, str):
                raise DataSafeHavenInputException(
                    f"Invalid value '{self.csv_path}' provided for argument 'csv'."
                )
            users.add(self.csv_path)
            return 0
        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not add users to Data Safe Haven '{environment_name}'.\n{str(exc)}".split(
                "\n"
            ):
                self.error(line)
        return 1

    def process_arguments(self) -> None:
        """Load command line arguments into attributes"""
        # Set a JSON-safe name for this SRE
        csv_path = self.argument("csv")
        if not isinstance(csv_path, str):
            raise DataSafeHavenInputException(
                f"Invalid value '{csv_path}' provided for 'name'."
            )
        self.csv_path = csv_path
        # Output
        output = self.option("output")
        if not isinstance(output, str) and (output is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{output}' provided for 'output'."
            )
        self.output = output
