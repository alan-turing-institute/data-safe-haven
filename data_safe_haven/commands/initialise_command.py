"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
import pathlib
import sys

# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.backend import Backend
from data_safe_haven.exceptions import DataSafeHavenException
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

    def handle(self):
        try:
            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.option("output"))

            # Request admin_group if not provided
            admin_group = self.option("admin-group")
            while not admin_group:
                admin_group = self.log_ask("Please enter the ID for an Azure group containing all administrators:", None)

            # Request location if not provided
            location = self.option("location")
            while not location:
                location = self.log_ask("Please enter the Azure location to deploy resources into:", None)

            # Request deployment_name if not provided
            deployment_name = self.option("deployment-name")
            while not deployment_name:
                deployment_name = self.log_ask("Please enter the name for this Data Safe Haven deployment:", None)

            # Request subscription_name if not provided
            subscription_name = self.option("subscription")
            while not subscription_name:
                subscription_name = self.log_ask("Please enter the Azure subscription to deploy resources into:", None)

            # Load settings from dotfiles
            settings = DotFileSettings(
                admin_group_id=admin_group,
                location=location,
                name=deployment_name,
                subscription_name=subscription_name,
            )

            # Ensure that the Pulumi backend exists
            backend = Backend(settings)
            backend.create()

            # Load the generated configuration object and upload it to blob storage
            config = backend.config
            config.upload()

            # Create a project directory and write the project settings there
            project_base_path = pathlib.Path.cwd().resolve() / config.name_sanitised
            if not project_base_path.exists():
                self.info(f"Creating project directory '<fg=green>{project_base_path}</>'.")
                project_base_path.mkdir()
            settings.write(project_base_path)

        except DataSafeHavenException as exc:
            for line in f"Could not initialise Data Safe Haven.\n{str(exc)}".split(
                "\n"
            ):
                self.error(line)
