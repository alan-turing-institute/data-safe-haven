"""Command-line application for tearing down a Data Safe Haven"""
from data_safe_haven.backend import Backend
from data_safe_haven.exceptions import (
    DataSafeHavenError,
    DataSafeHavenInputError,
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
                msg = f"Unable to teardown Pulumi backend.\n{exc}"
                raise DataSafeHavenInputError(msg) from exc
        except DataSafeHavenError as exc:
            msg = f"Could not teardown Data Safe Haven backend.\n{exc}"
            raise DataSafeHavenError(msg) from exc
