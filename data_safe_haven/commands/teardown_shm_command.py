"""Command-line application for tearing down a Data Safe Haven"""
# Local imports
from data_safe_haven.config import BackendSettings, Config
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.pulumi import PulumiStack


class TeardownSHMCommand:
    """Teardown a deployed a Safe Haven Management component"""

    def __call__(self) -> None:
        """Typer command line entrypoint"""
        try:
            # Use dotfile settings to load the job configuration
            try:
                settings = BackendSettings()
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
        except DataSafeHavenException as exc:
            raise DataSafeHavenException(
                f"Could not teardown Safe Haven Management component.\n{str(exc)}"
            ) from exc
