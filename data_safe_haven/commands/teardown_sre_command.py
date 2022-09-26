"""Command-line application for tearing down a Secure Research Environment"""
# Standard library imports
import pathlib
import sys

# Third party imports
from cleo import Command


# Local imports
from data_safe_haven.backend import Backend
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.pulumi import PulumiInterface


class TeardownSRECommand(LoggingMixin, Command):
    """
    Teardown a deployed Secure Research Environment using local configuration files

    sre
        {name : Name of SRE to deploy}
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

            # Remove infrastructure deployed with Pulumi
            try:
                infrastructure = PulumiInterface(
                    config, "SRE", sre_name=self.argument("name")
                )
                infrastructure.teardown()
            except Exception as exc:
                raise DataSafeHavenInputException(
                    f"Unable to teardown Pulumi infrastructure.\n{str(exc)}"
                ) from exc

            # Remove information from config file
            if infrastructure.stack_name in config.pulumi.stacks.keys():
                del config.pulumi.stacks[infrastructure.stack_name]
            if self.argument("name") in config.sre.keys():
                del config.sre[self.argument("name")]

            # Upload config to blob storage
            config.upload()
        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not teardown Data Safe Haven '{config.environment_name}'.\n{str(exc)}".split(
                "\n"
            ):
                self.error(line)
