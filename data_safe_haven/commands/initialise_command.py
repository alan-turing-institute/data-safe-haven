"""Command-line application for initialising a Data Safe Haven deployment"""
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
        {--l|location= : Name of the Azure location to use}
        {--o|output= : Path to an output log file}
        {--s|subscription= : Name of the Azure subscription to use}
    """

    def handle(self):
        try:
            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.option("output"))

            # Load settings from dotfiles
            settings = DotFileSettings(
                admin_group_id=self.option("admin-group"),
                location=self.option("location"),
                name=self.option("deployment-name"),
                subscription_name=self.option("subscription"),
            )

            # Ensure that the Pulumi backend exists
            backend = Backend(settings)
            backend.create()

            # Load the generated configuration object and upload it to blob storage
            config = backend.config
            config.upload()

        except DataSafeHavenException as exc:
            for line in f"Could not initialise Data Safe Haven.\n{str(exc)}".split(
                "\n"
            ):
                self.error(line)
