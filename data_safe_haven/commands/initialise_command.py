"""Command-line application for initialising a Data Safe Haven deployment"""
import pathlib
import sys
from cleo import Command
from data_safe_haven.config import Config
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.infrastructure import Backend, PulumiStack
from data_safe_haven.exceptions import DataSafeHavenInputException


class InitialiseCommand(LoggingMixin, Command):
    """
    Initialise a Data Safe Haven deployment

    init
        {--c|config= : Path to an input config YAML file}
        {--p|project= : Path to the output directory which should hold the project files}
    """

    def handle(self):
        config_path = self.option("config") if self.option("config") else "example.yaml"
        config = Config(config_path)

        # Ensure that the Pulumi backend exists
        backend = Backend(config)
        backend.create()

        # Initialise the Pulumi project directory
        template_path = pathlib.Path(__file__).parent.parent.parent / "templates"
        if not self.option("project"):
            raise DataSafeHavenInputException("No --project option was provide.")
        project_path = pathlib.Path(self.option("project"))
        if not project_path.exists():
            if not self.confirm(f"{self.prefix} Directory '{project_path}' does not exist. Create it?", False):
                sys.exit(0)
            project_path.mkdir()

        # Initialise the Pulumi project
        pulumi = PulumiStack(config, project_path=project_path, template_path=template_path)
        pulumi.initialise()

        # Upload config to blob storage
        self.info(f"Uploading config <fg=green>{config.name}</> to blob storage")
        config.upload()
