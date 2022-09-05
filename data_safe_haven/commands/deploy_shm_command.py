"""Command-line application for deploying a Data Safe Haven from project files"""
# Standard library imports
import ipaddress

# Third party imports
from cleo import Command
import yaml

# Local imports
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.pulumi import PulumiInterface
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.helpers import password


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
                raise DataSafeHavenInputException(
                    "Unable to load project settings. Please run this command from inside the project directory."
                )
            config = Config(settings.name, settings.subscription_name)
            self.add_missing_values(config)

            # Deploy infrastructure with Pulumi
            infrastructure = PulumiInterface(config, "SHM")
            infrastructure.add_option("azure-native:location", config.azure.location)
            infrastructure.add_option(
                "azure-native:subscriptionId", config.azure.subscription_id
            )
            infrastructure.add_secret("vm-password-primary-dc", password(20))
            infrastructure.deploy()

            # Add Pulumi output information to the config file
            with open(infrastructure.local_stack_path, "r") as f_stack:
                stack_yaml = yaml.safe_load(f_stack)
            config.pulumi.stack = stack_yaml

            # Upload config to blob storage
            config.upload()

        except DataSafeHavenException as exc:
            error_msg = (
                f"Could not deploy Data Safe Haven Management environment.\n{str(exc)}"
            )
            for line in error_msg.split("\n"):
                self.error(line)

    def add_missing_values(self, config: Config) -> None:
        """Request any missing config values and add them to the config"""
        # Request FQDN if not provided
        while not config.shm.fqdn:
            config.shm.fqdn = self.log_ask(
                "Please enter the domain that SHM users will belong to:", None
            )

        # Request FQDN if not provided
        while not config.shm.admin_ip_addresses:
            self.info(
                "We need to know any IP addresses or ranges that your system deployers and administrators will be connecting from."
            )
            self.info(
                "Please enter all of them at once, separated by spaces, for example '10.1.1.1  2.2.2.0/24  5.5.5.5'."
            )
            admin_ip_addresses = self.log_ask(
                "Space-separated administrator IP addresses and ranges:", None
            )
            config.shm.admin_ip_addresses = [
                str(ipaddress.ip_network(ipv4))
                for ipv4 in admin_ip_addresses.split()
                if ipv4
            ]
