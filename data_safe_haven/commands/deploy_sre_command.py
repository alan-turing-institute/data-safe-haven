"""Command-line application for deploying a Secure Research Environment from project files"""
# Standard library imports
import pathlib

# Third party imports
from cleo import Command
import yaml

# Local imports
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.pulumi import PulumiInterface
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.provisioning import ContainerProvisioner, PostgreSQLProvisioner


class DeploySRECommand(LoggingMixin, Command):
    """
    Deploy a Secure Research Environment using local configuration and project files

    sre
        {--o|output= : Path to an output log file}
    """

    def handle(self):
        try:
            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.option("output"))

            # Use dotfile settings to load the job configuration
            try:
                settings = DotFileSettings()
            except DataSafeHavenInputException:
                raise DataSafeHavenInputException(
                    "Unable to load project settings. Please run this command from inside the project directory."
                )
            config = Config(settings.name, settings.subscription_name)

            # Deploy infrastructure with Pulumi
            infrastructure = PulumiInterface(config, "SRE")
            infrastructure.deploy()
            infrastructure.update_config()

            # Add Pulumi output information to the config file
            with open(infrastructure.local_stack_path, "r") as f_stack:
                stack_yaml = yaml.safe_load(f_stack)
            config.pulumi.stack = stack_yaml

            # Upload config to blob storage
            config.upload()

            # Provision Guacamole
            # -------------------

            # Provision the Guacamole PostgreSQL server
            postgres_provisioner = PostgreSQLProvisioner(
                config,
                config.pulumi.outputs.guacamole.resource_group_name,
                config.pulumi.outputs.guacamole.postgresql_server_name,
                infrastructure.secret("guacamole-postgresql-password"),
            )
            connections = infrastructure.output("vm_details")
            connection_data = {
                "connections": [
                    {
                        "connection_name": connection,
                        "disable_copy": (not config.settings.allow_copy),
                        "disable_paste": (not config.settings.allow_paste),
                        "ip_address": ip_address,
                        "timezone": config.settings.timezone,
                    }
                    for (connection, ip_address) in connections
                ]
            }
            postgres_script_path = (
                pathlib.Path(__file__).parent.parent
                / "resources"
                / "guacamole"
                / "postgresql"
            )
            postgres_provisioner.execute_scripts(
                [
                    postgres_script_path / "init_db.sql",
                    postgres_script_path / "update_connections.mustache.sql",
                ],
                mustache_values=connection_data,
            )

            # Restart the Guacamole container group
            guacamole_provisioner = ContainerProvisioner(
                config,
                config.pulumi.outputs.guacamole.resource_group_name,
                config.pulumi.outputs.guacamole.container_group_name,
            )
            guacamole_provisioner.restart()
        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not deploy Secure Research Environment.\n{str(exc)}".split(
                "\n"
            ):
                self.error(line)
