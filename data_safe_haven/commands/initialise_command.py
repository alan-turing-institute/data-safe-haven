"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
import pathlib
import sys
from typing import Optional

# Local imports
from data_safe_haven.backend import Backend
from data_safe_haven.config import BackendSettings
from data_safe_haven.exceptions import DataSafeHavenException
from data_safe_haven.utility import Logger


class InitialiseCommand:
    """Initialise a Data Safe Haven deployment"""

    def __init__(self):
        """Constructor"""
        self.logger = Logger()

    def __call__(
        self,
        admin_group: Optional[str] = None,
        location: Optional[str] = None,
        name: Optional[str] = None,
        subscription: Optional[str] = None,
    ) -> None:
        """Typer command line entrypoint"""
        try:
            # Create/update backend settings with command line arguments (if provided)
            _ = BackendSettings(
                admin_group_id=admin_group,
                location=location,
                name=name,
                subscription_name=subscription,
            )

            # Ensure that the Pulumi backend exists
            backend = Backend()
            backend.create()

            # Load the generated configuration file and upload it to blob storage
            config = backend.config
            config.upload()

        except DataSafeHavenException as exc:
            raise DataSafeHavenException(
                f"Could not initialise Data Safe Haven.\n{str(exc)}"
            ) from exc
