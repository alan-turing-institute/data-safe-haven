"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
import pathlib
import sys

# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.backend import Backend
from data_safe_haven.config import Config
from data_safe_haven.exceptions import DataSafeHavenException
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.pulumi import PulumiInterface


class UsersCommand(LoggingMixin, Command):
    """
    User management for a Data Safe Haven deployment

    users
        {--a|add= : Add one or more users from a CSV file}
        {--c|config= : Path to an input config YAML file}
        {--l|list : List available users}
        {--o|output= : Path to an output log file}
        {--p|project= : Path to the output directory which will hold the project files}
        {--r|remove=* : Remove the specified user by username}
        {--s|set= : Set list of users to match those in a CSV file}
    """

    def handle(self):
        try:
            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.option("output"))

            # Load the job configuration
            config_path = (
                self.option("config") if self.option("config") else "example.yaml"
            )
            config = Config(config_path)

            # Check that the project directory exists
            if self.option("project"):
                project_path = pathlib.Path(self.option("project"))
            else:
                project_path = pathlib.Path(config_path).parent.resolve()
            if not project_path.exists():
                self.warning(f"Project path '{project_path}' does not exist.")
                sys.exit(0)

            # Read backend secrets
            backend = Backend(config)
            aad_application_id = backend.get_secret(
                config.backend.key_vault_name, "azuread-user-management-application-id"
            )
            aad_application_secret = backend.get_secret(
                config.backend.key_vault_name,
                "azuread-user-management-application-secret",
            )

            # Load users interface
            infrastructure = PulumiInterface(config, project_path)
            users = UserHandler(
                config,
                aad_application_id,
                aad_application_secret,
                infrastructure.secret("guacamole-postgresql-password"),
            )

            # Add one or more users
            if self.option("add"):
                users.add(self.option("add"))

            # Print table of users
            if self.option("list"):
                users.list()

            # Remove one or more users
            if self.option("remove"):
                users.remove(self.option("remove"))

            # Set list of users
            if self.option("set"):
                users.set(self.option("set"))

            # Upload config to blob storage
            config.upload()
        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not manage users Data Safe Haven '{config.environment_name}'.\n{str(exc)}".split(
                "\n"
            ):
                self.error(line)
