"""Command-line application for initialising a Data Safe Haven deployment"""
# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.backend import Backend
from data_safe_haven.mixins import LoggingMixin


class InitialiseCommand(LoggingMixin, Command):
    """
    Initialise a Data Safe Haven deployment

    init
        {--c|config= : Path to an input config YAML file}
        {--o|output= : Path to an output log file}
    """

    def handle(self):
        # Set up logging for anything called by this command
        self.initialise_logging(self.io.verbosity, self.option("output"))

        # Load the job configuration
        config_path = self.option("config") if self.option("config") else "example.yaml"
        config = Config(config_path)

        # Ensure that the Pulumi backend exists
        backend = Backend(config)
        backend.create()
        backend.update_config()

        # Upload config to blob storage
        config.upload()
