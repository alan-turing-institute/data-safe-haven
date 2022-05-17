"""Command-line application for deploying a Data Safe Haven from project files"""
# Standard library imports
import pathlib
import sys

# Third party imports
from cleo import Command
import yaml

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.infrastructure import PulumiInterface
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.provisioning import ContainerProvisioner, PostgreSQLProvisioner


class DeployCommand(LoggingMixin, Command):
    """
    Deploy a Data Safe Haven using local configuration and project files

    deploy
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
            if not self.confirm(
                f"{self.prefix} Directory '{project_path}' does not exist. Create it?",
                False,
            ):
                sys.exit(0)
            project_path.mkdir()

        # Deploy infrastructure with Pulumi
        infrastructure = PulumiInterface(config, project_path)
        infrastructure.deploy()

        # Add Pulumi output information to the config file
        with open(infrastructure.local_stack_path, "r") as f_stack:
            stack_yaml = yaml.safe_load(f_stack)
        config.pulumi.stack = stack_yaml
        config.add_data(
            {
                "pulumi": {
                    "outputs": {
                        "authentication": {
                            "container_group_name": infrastructure.output(
                                "auth_container_group_name"
                            ),
                            "file_share_name_ldifs": infrastructure.output(
                                "auth_file_share_name_ldifs"
                            ),
                            "resource_group_name": infrastructure.output(
                                "auth_resource_group_name"
                            ),
                        },
                        "guacamole": {
                            "container_group_name": infrastructure.output(
                                "guacamole_container_group_name"
                            ),
                            "postgresql_server_name": infrastructure.output(
                                "guacamole_postgresql_server_name"
                            ),
                            "resource_group_name": infrastructure.output(
                                "guacamole_resource_group_name"
                            ),
                        },
                        "state": {
                            "resource_group_name": infrastructure.output(
                                "state_resource_group_name"
                            ),
                            "storage_account_name": infrastructure.output(
                                "state_storage_account_name"
                            ),
                        },
                    }
                }
            }
        )

        # Upload config to blob storage
        config.upload()

        # Provision authentication
        # ------------------------

        # Restart the authentication container group
        authentication_provisioner = ContainerProvisioner(
            config,
            config.pulumi.outputs.authentication.resource_group_name,
            config.pulumi.outputs.authentication.container_group_name,
        )
        authentication_provisioner.restart()

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
