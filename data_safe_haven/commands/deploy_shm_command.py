"""Command-line application for deploying a Data Safe Haven from project files"""
# Third party imports
from cleo import Command
import yaml

# Local imports
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import DataSafeHavenException, DataSafeHavenInputException
from data_safe_haven.pulumi import PulumiInterface
from data_safe_haven.mixins import LoggingMixin


class DeploySHMCommand(LoggingMixin, Command):
    """
    Deploy a Data Safe Haven using local configuration and project files

    deploy-shm
        {--o|output= : Path to an output log file}
    """

    def handle(self):
        try:
            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.option("output"))

            # Use dotfile settings to load the job configuration
            try:
                settings = DotFileSettings()
            except DataSafeHavenInputException:
                raise DataSafeHavenInputException("Unable to load project settings. Please run this command from inside the project directory.")
            config = Config(settings.name, settings.subscription_name)

            # Request FQDN if not provided
            while not config.shm.fqdn:
                config.shm.fqdn = self.log_ask("Please enter the domain that SHM users will belong to:", None)

            # Deploy infrastructure with Pulumi
            infrastructure = PulumiInterface(config, "SHM")
            infrastructure.deploy()

            # Add Pulumi output information to the config file
            with open(infrastructure.local_stack_path, "r") as f_stack:
                stack_yaml = yaml.safe_load(f_stack)
            config.pulumi.stack = stack_yaml

            # Upload config to blob storage
            config.upload()

        except DataSafeHavenException as exc:
            error_msg = f"Could not deploy Data Safe Haven Management environment.\n{str(exc)}"
            for line in error_msg.split("\n"):
                self.error(line)
