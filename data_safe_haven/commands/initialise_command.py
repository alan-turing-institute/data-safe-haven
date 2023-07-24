"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
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
        admin_group: str | None = None,
        location: str | None = None,
        name: str | None = None,
        subscription: str | None = None,
    ) -> None:
        """Typer command line entrypoint"""
        try:
            # Load backend settings and update with command line arguments
            settings = BackendSettings()
            settings.update(
                admin_group_id=admin_group,
                location=location,
                name=name,
                subscription_name=subscription,
            )

            # Ensure that the Pulumi backend exists
            backend = Backend()
            backend.create()

            # Load the generated configuration file and upload it to blob storage
            backend.config.upload()

        except DataSafeHavenException as exc:
            msg = f"Could not initialise Data Safe Haven.\n{exc!s}"
            raise DataSafeHavenException(msg) from exc
