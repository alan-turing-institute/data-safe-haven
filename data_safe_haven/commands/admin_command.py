"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
import pathlib
import sys

# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.administration import Users
from data_safe_haven.infrastructure import PulumiInterface


class AdminCommand(LoggingMixin, Command):
    """
    Administration for a Data Safe Haven deployment

    admin
        {--a|add= : Add one or more users from a CSV file}
        {--c|config= : Path to an input config YAML file}
        {--l|list : List available users}
        {--o|output= : Path to an output log file}
        {--p|project= : Path to the output directory which will hold the project files}
    """

    def handle(self):
        # Set up logging for anything called by this command
        self.initialise_logging(self.io.verbosity, self.option("output"))

        # Load the job configuration
        config_path = self.option("config") if self.option("config") else "example.yaml"
        config = Config(config_path)

        # Check that the project directory exists
        if self.option("project"):
            project_path = pathlib.Path(self.option("project"))
        else:
            project_path = pathlib.Path(config_path).parent.resolve()
        if not project_path.exists():
            self.warning(f"Project path '{project_path}' does not exist.")
            sys.exit(0)

        # Load users interface
        infrastructure = PulumiInterface(config, project_path)
        users = Users(config, infrastructure.secret("guacamole-postgresql-password"))

        # Add one or more users
        if self.option("add"):
            users.add(self.option("add"))

        # Print table of users
        if self.option("list"):
            users.list()

        # Upload config to blob storage
        config.upload()
