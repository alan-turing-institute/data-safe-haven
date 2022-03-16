"""Command-line application for deploying a Data Safe Haven from project files"""
# Standard library imports
import pathlib
import sys

# Third party imports
from cleo import Command
import yaml

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.deployment import PulumiCreate
from data_safe_haven.mixins import LoggingMixin


class DeployCommand(LoggingMixin, Command):
    """
    Deploy a Data Safe Haven from project files

    deploy
        {--c|config= : Path to an input config YAML file}
        {--p|project= : Path to the output directory which will hold the project files}
    """

    def handle(self):
        config_path = self.option("config") if self.option("config") else "example.yaml"
        config = Config(config_path)

        # Ensure that the project directory exists
        if self.option("project"):
            project_path = pathlib.Path(self.option("project"))
        else:
            project_path = pathlib.Path(config_path).parent.resolve()
            self.warning(f"No --project option was provided. Using '{project_path}'.")
        if not project_path.exists():
            if not self.confirm(
                f"{self.prefix} Directory '{project_path}' does not exist. Create it?",
                False,
            ):
                sys.exit(0)
            project_path.mkdir()

        # Deploy infrastructure with Pulumi
        pulumi = PulumiCreate(config, project_path)
        pulumi.apply()

        # Add stack information config
        with open(pulumi.local_stack_path, "r") as f_stack:
            stack_yaml = yaml.safe_load(f_stack)
        config.pulumi.stack = stack_yaml

        # Upload config to blob storage
        self.info(f"Uploading config <fg=green>{config.name}</> to blob storage")
        config.upload()

        # Write kubeconfig to the project directory
        self.info(
            f"Writing kubeconfig to <fg=green>{config.project_directory.kubernetes}</>."
        )
        pulumi.write_kubeconfig(config.project_directory.kubernetes)
