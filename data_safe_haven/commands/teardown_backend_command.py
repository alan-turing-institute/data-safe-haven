"""Command-line application for tearing down a Data Safe Haven"""
# Local imports
from data_safe_haven.backend import Backend
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)


class TeardownBackendCommand:
    """Tear down a deployed Data Safe Haven backend"""

    def __call__(self) -> None:
        """Typer command line entrypoint"""
        try:
            # Remove the Pulumi backend
            try:
                backend = Backend()
                backend.teardown()
            except Exception as exc:
                raise DataSafeHavenInputException(
                    f"Unable to teardown Pulumi backend.\n{str(exc)}"
                ) from exc
        except DataSafeHavenException as exc:
            raise DataSafeHavenException(
                f"Could not teardown Data Safe Haven backend.\n{str(exc)}"
            ) from exc
