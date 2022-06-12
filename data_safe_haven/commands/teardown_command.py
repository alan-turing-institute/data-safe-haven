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
from data_safe_haven.exceptions import DataSafeHavenException, DataSafeHavenInputException
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
        try:
            try:
                config_path = self.option("config") if self.option("config") else "example.yaml"
                config = Config(config_path)
            except Exception as exc:
                raise DataSafeHavenInputException(f"Unable to load Data Safe Haven configuration.\n{str(exc)}") from exc

            # Ensure that the project directory exists
            if self.option("project"):
                project_path = pathlib.Path(self.option("project"))
            else:
                project_path = pathlib.Path(config_path).parent.resolve()
                self.warning(f"No --project option was provided. Using '{project_path}'.")
            if not project_path.exists():
                raise DataSafeHavenInputException("Unable to load project directory.")

            try:
                # Remove infrastructure deployed with Pulumi
                if config.backend_exists():
                    infrastructure = PulumiInterface(config, project_path)
                    infrastructure.teardown()
            except Exception as exc:
                raise DataSafeHavenInputException(f"Unable to teardown Pulumi infrastructure.\n{str(exc)}") from exc

            try:
                # Remove the Pulumi backend
                if config.backend_exists():
                    backend = Backend(config)
                    backend.teardown()
            except Exception as exc:
                raise DataSafeHavenInputException(f"Unable to teardown Pulumi backend.\n{str(exc)}") from exc

            try:
                # Remove Pulumi path
                pulumi_path = project_path / "pulumi"
                self.info(f"Removing Pulumi data from project directory '{pulumi_path}'.")
                if pulumi_path.exists():
                    shutil.rmtree(pulumi_path)
            except Exception as exc:
                raise DataSafeHavenInputException(f"Unable to remove project directory '{pulumi_path}'.")

        except DataSafeHavenException as exc:
            for line in f"Could not teardown Data Safe Haven '{config.environment_name}'.\n{str(exc)}".split("\n"):
                self.error(line)

