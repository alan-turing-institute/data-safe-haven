"""Command-line application for tearing down a Data Safe Haven"""
# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.backend import Backend
from data_safe_haven.config import DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.mixins import LoggingMixin


class TeardownBackendCommand(LoggingMixin, Command):
    """
    Teardown a deployed Data Safe Haven backend using local configuration files

    backend
    """

    def handle(self):
        try:
            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.option("output"))

            # Use dotfile settings to load the job configuration
            try:
                settings = DotFileSettings()
            except DataSafeHavenInputException as exc:
                raise DataSafeHavenInputException(
                    f"Unable to load project settings. Please run this command from inside the project directory.\n{str(exc)}"
                ) from exc

            # Remove the Pulumi backend
            try:
                backend = Backend(settings)
                backend.teardown()
            except Exception as exc:
                raise DataSafeHavenInputException(
                    f"Unable to teardown Pulumi backend.\n{str(exc)}"
                ) from exc

        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not teardown Data Safe Haven backend.\n{str(exc)}".split("\n"):
                self.error(line)
