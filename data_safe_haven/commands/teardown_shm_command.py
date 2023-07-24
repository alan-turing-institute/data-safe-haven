"""Command-line application for tearing down a Data Safe Haven"""
# Local imports
from data_safe_haven.config import Config
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.pulumi import PulumiSHMStack


class TeardownSHMCommand:
    """Teardown a deployed a Safe Haven Management component"""

    def __call__(self) -> None:
        """Typer command line entrypoint"""
        try:
            # Load config file
            config = Config()

            # Remove infrastructure deployed with Pulumi
            try:
                stack = PulumiSHMStack(config)
                stack.teardown()
            except Exception as exc:
                msg = f"Unable to teardown Pulumi infrastructure.\n{exc!s}"
                raise DataSafeHavenInputException(msg) from exc

            # Remove information from config file
            if stack.stack_name in config.pulumi.stacks.keys():
                del config.pulumi.stacks[stack.stack_name]

            # Upload config to blob storage
            config.upload()
        except DataSafeHavenException as exc:
            msg = f"Could not teardown Safe Haven Management component.\n{exc!s}"
            raise DataSafeHavenException(msg) from exc
