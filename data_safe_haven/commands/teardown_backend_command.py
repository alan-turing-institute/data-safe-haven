"""Command-line application for tearing down a Data Safe Haven"""
# Local imports
from data_safe_haven.backend import Backend
from data_safe_haven.config import DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from .base_command import BaseCommand


class TeardownBackendCommand(BaseCommand):
    """Tear down a deployed Data Safe Haven backend"""

    def entrypoint(self) -> None:
        """Typer command line entrypoint"""
        try:
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
            raise DataSafeHavenException(
                f"Could not teardown Data Safe Haven backend.\n{str(exc)}"
            ) from exc
