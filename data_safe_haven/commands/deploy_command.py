"""Command-line application for deploying a Data Safe Haven from project files"""
# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.exceptions import DataSafeHavenException, DataSafeHavenInputException
from data_safe_haven.mixins import LoggingMixin
from .deploy_shm_command import DeploySHMCommand
from .deploy_sre_command import DeploySRECommand


class DeployCommand(LoggingMixin, Command):
    """
    Deploy a Data Safe Haven using local configuration and project files

    deploy
        {deployment-type : Whether to deploy a Safe Haven Management environment ('shm') or a Secure Research Environment ('sre')}
        {--o|output= : Path to an output log file}
        {--p|project= : Path to the base directory which will hold the project files for this deployment}
    """

    def handle(self):
        try:
            # Read the arguments
            if self.argument("deployment-type") == "shm":
                command = DeploySHMCommand()
            elif self.argument("deployment-type") == "sre":
                command = DeploySRECommand()
            else:
                raise DataSafeHavenInputException(f"Argument '{self.argument('deployment-type')}' cannot be interpreted as a deployment type.")
            command._args = self._args
            command._io = self._io
            command.handle()
        except DataSafeHavenException as exc:
            error_msg = f"Could not deploy Data Safe Haven.\n{str(exc)}"
            for line in error_msg.split("\n"):
                self.error(line)
