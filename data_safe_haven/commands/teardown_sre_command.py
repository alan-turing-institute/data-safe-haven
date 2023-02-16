"""Command-line application for tearing down a Secure Research Environment"""
# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.pulumi import PulumiStack


class TeardownSRECommand(LoggingMixin, Command):
    """
    Teardown a deployed Secure Research Environment using local configuration files

    sre
        {name : Name of SRE to deploy}
        {--o|output= : Path to an output log file}
    """

    def handle(self):
        environment_name = "UNKNOWN"
        try:
            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.option("output"))

            # Use dotfile settings to load the job configuration
            try:
                settings = DotFileSettings()
            except DataSafeHavenException as exc:
                raise DataSafeHavenInputException(
                    f"Unable to load project settings. Please run this command from inside the project directory.\n{str(exc)}"
                ) from exc
            config = Config(settings.name, settings.subscription_name)
            environment_name = config.name

            # Remove infrastructure deployed with Pulumi
            try:
                name = self.argument("name")
                if not isinstance(name, str):
                    raise DataSafeHavenInputException(
                        f"Invalid value '{name}' provided for option 'name'."
                    )
                stack = PulumiStack(config, "SRE", sre_name=name)
                if stack.work_dir.exists():
                    stack.teardown()
                else:
                    raise DataSafeHavenInputException(
                        f"SRE {self.argument('name')} not found - check the name is spelt correctly."
                    )
            except Exception as exc:
                raise DataSafeHavenInputException(
                    f"Unable to teardown Pulumi infrastructure.\n{str(exc)}"
                ) from exc

            # Remove information from config file
            if stack.stack_name in config.pulumi.stacks.keys():
                del config.pulumi.stacks[stack.stack_name]
            if self.argument("name") in config.sre.keys():
                del config.sre[self.argument("name")]

            # Upload config to blob storage
            config.upload()
        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not teardown Data Safe Haven '{environment_name}'.\n{str(exc)}".split(
                "\n"
            ):
                self.error(line)
