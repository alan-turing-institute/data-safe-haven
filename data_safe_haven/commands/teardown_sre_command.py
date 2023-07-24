"""Command-line application for tearing down a Secure Research Environment"""
# Local imports
from data_safe_haven.config import Config
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.functions import alphanumeric
from data_safe_haven.pulumi import PulumiSREStack


class TeardownSRECommand:
    """Teardown a deployed Secure Research Environment"""

    def __call__(
        self,
        name: str,
    ) -> None:
        """Typer command line entrypoint"""
        environment_name = "UNKNOWN"
        try:
            # Use a JSON-safe SRE name
            sre_name = alphanumeric(name).lower()

            # Load config file
            config = Config()
            environment_name = config.name

            # Remove infrastructure deployed with Pulumi
            try:
                stack = PulumiSREStack(config, sre_name)
                if stack.work_dir.exists():
                    stack.teardown()
                else:
                    msg = f"SRE {sre_name} not found - check the name is spelt correctly."
                    raise DataSafeHavenInputException(msg)
            except Exception as exc:
                msg = f"Unable to teardown Pulumi infrastructure.\n{exc!s}"
                raise DataSafeHavenInputException(msg) from exc

            # Remove information from config file
            config.remove_stack(stack.stack_name)
            config.remove_sre(sre_name)

            # Upload config to blob storage
            config.upload()
        except DataSafeHavenException as exc:
            msg = f"Could not teardown Data Safe Haven '{environment_name}'.\n{exc!s}"
            raise DataSafeHavenException(msg) from exc
