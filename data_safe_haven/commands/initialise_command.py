"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
import pathlib
import sys

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
        {--p|project= : Path to the output directory which will hold the project files}
    """

    def handle(self):
        config_path = self.option("config") if self.option("config") else "example.yaml"
        config = Config(config_path)

        # Ensure that the Pulumi backend exists
        backend = Backend(config)
        backend.create()

        # Ensure that the project directory exists
        if self.option("project"):
            project_path = pathlib.Path(self.option("project"))
        else:
            project_path = (
                pathlib.Path.home() / ".data_safe_haven" / config.deployment_name
            )
            self.error(f"No --project option was provided. Using '{project_path}'.")
        if not project_path.exists():
            if not self.confirm(
                f"{self.prefix} Directory '{project_path}' does not exist. Create it?",
                False,
            ):
                sys.exit(0)
            project_path.mkdir()

        # Add the project directory and subdirectories to the config
        config.add_property(
            "project_directory",
            {
                "base": str(project_path.resolve()),
                "pulumi": str(project_path.resolve() / "pulumi"),
                "kubernetes": str(project_path.resolve() / "kubernetes"),
            },
        )

        # Upload config to blob storage
        self.info(f"Uploading config <fg=green>{config.name}</> to blob storage")
        config.upload()
