"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
import pathlib
import sys
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
from data_safe_haven.mixins import LoggingMixin


class InitialiseCommand(LoggingMixin, Command):
    """
    Initialise a Data Safe Haven deployment

    init
        {--a|admin-group= : ID of the Azure group containing all administrators}
        {--d|deployment-name= : Name for this Data Safe Haven deployment}
        {--l|location= : Name of the Azure location to deploy into}
        {--o|output= : Path to an output log file}
        {--s|subscription= : Name of the Azure subscription to deploy into}
    """

    admin_group: Optional[str]
    deployment_name: Optional[str]
    location: Optional[str]
    output: Optional[str]
    subscription: Optional[str]

    def handle(self) -> int:
        try:
            # Process command line arguments
            self.process_arguments()

            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.output)

            # Confirm project path
            project_base_path = pathlib.Path.cwd().resolve()
            if not self.log_confirm(
                f"Do you want to initialise a Data Safe Haven project at <fg=green>{project_base_path}</>?",
                True,
            ):
                sys.exit(0)

            # Load settings from dotfiles
            settings = DotFileSettings(
                admin_group_id=self.admin_group,
                location=self.location,
                name=self.deployment_name,
                subscription_name=self.subscription,
            )

            # Ensure that the Pulumi backend exists
            backend = Backend(settings)
            backend.create()

            # Load the generated configuration object and upload it to blob storage
            config = backend.config
            config.upload()

            # Ensure that the project directory exists
            if not project_base_path.exists():
                self.info(
                    f"Creating project directory '<fg=green>{project_base_path}</>'."
                )
                project_base_path.mkdir(parents=True)
            settings_path = settings.write(project_base_path)
            self.info(f"Saved project settings to '<fg=green>{settings_path}</>'.")
            return 0
        except DataSafeHavenException as exc:
            for line in f"Could not initialise Data Safe Haven.\n{str(exc)}".split(
                "\n"
            ):
                self.error(line)
        return 1

    def process_arguments(self) -> None:
        """Load command line arguments into attributes"""
        # Admin group
        admin_group = self.option("admin-group")
        if not isinstance(admin_group, str) and (admin_group is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{admin_group}' provided for 'admin-group'."
            )
        self.admin_group = admin_group
        # Deployment name
        deployment_name = self.option("deployment-name")
        if not isinstance(deployment_name, str) and (deployment_name is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{deployment_name}' provided for 'deployment-name'."
            )
        self.deployment_name = deployment_name
        # Location
        location = self.option("location")
        if not isinstance(location, str) and (location is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{location}' provided for 'location'."
            )
        self.location = location
        # Output
        output = self.option("output")
        if not isinstance(output, str) and (output is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{output}' provided for 'output'."
            )
        self.output = output
        # Subscription
        subscription = self.option("subscription")
        if not isinstance(subscription, str) and (subscription is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{subscription}' provided for 'subscription'."
            )
        self.subscription = subscription
