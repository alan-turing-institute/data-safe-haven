"""Command-line application for tearing down a Data Safe Haven"""
# Standard library imports
from typing import Optional

# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.pulumi import PulumiStack
from data_safe_haven.utility import Logger


class TeardownSHMCommand(Command):  # type: ignore
    """
    Teardown a deployed a Safe Haven Management component using local configuration files

    shm
        {--o|output= : Path to an output log file}
    """

    output: Optional[str]

    def handle(self) -> int:
        try:
            # Process command line arguments
            self.process_arguments()

            # Set up logging for anything called by this command
            self.logger = Logger(self.io.verbosity, self.output)

            # Use dotfile settings to load the job configuration
            try:
                settings = DotFileSettings()
            except DataSafeHavenInputException as exc:
                raise DataSafeHavenInputException(
                    f"Unable to load project settings. Please run this command from inside the project directory.\n{str(exc)}"
                ) from exc
            config = Config(settings.name, settings.subscription_name)

            # Remove infrastructure deployed with Pulumi
            try:
                stack = PulumiStack(config, "SHM")
                stack.teardown()
            except Exception as exc:
                raise DataSafeHavenInputException(
                    f"Unable to teardown Pulumi infrastructure.\n{str(exc)}"
                ) from exc

            # Remove information from config file
            if stack.stack_name in config.pulumi.stacks.keys():
                del config.pulumi.stacks[stack.stack_name]
            if config.shm.keys():
                del config._map.shm

            # Upload config to blob storage
            config.upload()
            return 0
        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not teardown Safe Haven Management component.\n{str(exc)}".split(
                "\n"
            ):
                self.logger.error(line)
        return 1

    def process_arguments(self) -> None:
        """Load command line arguments into attributes"""
        # Output
        output = self.option("output")
        if not isinstance(output, str) and (output is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{output}' provided for 'output'."
            )
        self.output = output
