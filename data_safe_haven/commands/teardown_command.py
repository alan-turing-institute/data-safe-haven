"""Command-line application for deploying a Data Safe Haven from project files"""
# Standard library imports
import pathlib
import shutil
import sys

# Third party imports
from cleo import Command


# Local imports
from data_safe_haven.backend import Backend
from data_safe_haven.config import Config
from data_safe_haven.infrastructure import PulumiInterface
from data_safe_haven.mixins import LoggingMixin


class TeardownCommand(LoggingMixin, Command):
    """
    Teardown a deployed Data Safe Haven using local configuration and project files

    teardown
        {--c|config= : Path to an input config YAML file}
        {--o|output= : Path to an output log file}
        {--p|project= : Path to the output directory which will hold the project files}
    """

    def handle(self):
        # Set up logging for anything called by this command
        self.initialise_logging(self.io.verbosity, self.option("output"))

        # Load the job configuration
        config_path = self.option("config") if self.option("config") else "example.yaml"
        config = Config(config_path)

        # Ensure that the project directory exists
        if self.option("project"):
            project_path = pathlib.Path(self.option("project"))
        else:
            project_path = pathlib.Path(config_path).parent.resolve()
            self.warning(f"No --project option was provided. Using '{project_path}'.")
        if not project_path.exists():
            sys.exit(0)

        if config.backend_exists():
            # Remove infrastructure deployed with Pulumi
            infrastructure = PulumiInterface(config, project_path)
            infrastructure.teardown()

            # Remove the Pulumi backend
            backend = Backend(config)
            backend.destroy()
        else:
            self.warning(
                f"Could not load config variables - has Data Safe Haven '{config.environment_name}' already been deleted?"
            )

        # Remove Pulumi path
        pulumi_path = project_path / "pulumi"
        self.info(f"Removing Pulumi data from project directory '{pulumi_path}'.")
        shutil.rmtree(pulumi_path)
