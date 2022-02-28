"""Command-line application for initialising a Data Safe Haven deployment"""
from cleo import Command
from data_safe_haven.config import Config
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.pulumi import Backend


class InitialiseCommand(Command, LoggingMixin):
    """
    Initialise a Data Safe Haven deployment

    init
        {--c|config= : Path to a config YAML file}
    """

    cfg = None
    subscription_id = None
    tenant_id = None

    def handle(self):
        config_path = self.option("config") if self.option("config") else "example.yaml"
        self.cfg = Config(config_path)

        # Ensure that the Pulumi backend exists
        backend = Backend(self.cfg)
        backend.create()
