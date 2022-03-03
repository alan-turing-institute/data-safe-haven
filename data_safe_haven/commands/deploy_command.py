"""Command-line application for deploying a Data Safe Haven from project files"""
from cleo import Command
from data_safe_haven.config import Config
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.deployment import PulumiDeploy


class DeployCommand(LoggingMixin, Command):
    """
    Deploy a Data Safe Haven from project files

    deploy
        {--c|config= : Path to an input config YAML file}
        {--p|project= : Path to the output Pulumi project}
    """

    def handle(self):
        config_path = self.option("config") if self.option("config") else "example.yaml"
        config = Config(config_path)

        # Deploy with Pulumi
        pulumi = PulumiDeploy(config, project_path=self.option("project"))
        pulumi.deploy()
