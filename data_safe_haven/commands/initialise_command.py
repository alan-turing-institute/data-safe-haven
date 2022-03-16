"""Command-line application for initialising a Data Safe Haven deployment"""
# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.infrastructure import Backend
from data_safe_haven.mixins import LoggingMixin


class InitialiseCommand(LoggingMixin, Command):
    """
    Initialise a Data Safe Haven deployment

    init
        {--c|config= : Path to an input config YAML file}
    """

    def handle(self):
        config_path = self.option("config") if self.option("config") else "example.yaml"
        config = Config(config_path)

        # Ensure that the Pulumi backend exists
        backend = Backend(config)
        backend.create()

        # Upload config to blob storage
        self.info(f"Uploading config <fg=green>{config.name}</> to blob storage")
        config.upload()
