"""Command-line application for tearing down a Data Safe Haven"""
# Local imports
from data_safe_haven.config import Config
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
            # Load config file
            config = Config()

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

            # Upload config to blob storage
            config.upload()
        except DataSafeHavenException as exc:
            raise DataSafeHavenException(
                f"Could not teardown Safe Haven Management component.\n{str(exc)}"
            ) from exc
