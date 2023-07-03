"""Command-line application for tearing down a Data Safe Haven"""
# Standard library imports
from typing import Optional

# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.backend import Backend
from data_safe_haven.config import DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.utility import Logger


class TeardownBackendCommand(Command):  # type: ignore
    """
    Teardown a deployed Data Safe Haven backend using local configuration files

    backend
        {--o|output= : Path to an output log file}
    """

    output: Optional[str]

    def handle(self) -> int:
        try:
            # Process command line arguments
            self.process_arguments()

            # Set up logging for anything called by this command
            self.logger = Logger(self.io.verbosity, self.output)

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
            return 0
        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not teardown Data Safe Haven backend.\n{str(exc)}".split("\n"):
                self.logger.error(line)
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
