"""Command-line application for deploying a Data Safe Haven from project files"""
# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.deployment import PulumiCreate
from data_safe_haven.mixins import LoggingMixin


class DeployCommand(LoggingMixin, Command):
    """
    Deploy a Data Safe Haven from project files

    deploy
        {--c|config= : Path to an input config YAML file}
    """

    def handle(self):
        config_path = self.option("config") if self.option("config") else "example.yaml"
        config = Config(config_path)

        # Deploy infrastructure with Pulumi
        pulumi = PulumiCreate(config)
        pulumi.apply()

        # Write kubeconfig to the project directory
        self.info(
            f"Writing kubeconfig to <fg=green>{config.project_directory.kubernetes}</>."
        )
        pulumi.write_kubeconfig(config.project_directory.kubernetes)
