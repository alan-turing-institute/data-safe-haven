"""Command-line application for tearing down a Secure Research Environment"""
# Local imports
from data_safe_haven.config import BackendSettings, Config
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.functions import alphanumeric
from data_safe_haven.pulumi import PulumiStack


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
            sre_name = alphanumeric(name)

            # Use dotfile settings to load the job configuration
            try:
                settings = BackendSettings()
            except DataSafeHavenException as exc:
                raise DataSafeHavenInputException(
                    f"Unable to load project settings. Please run this command from inside the project directory.\n{str(exc)}"
                ) from exc
            config = Config(settings.name, settings.subscription_name)
            environment_name = config.name

            # Remove infrastructure deployed with Pulumi
            try:
                stack = PulumiStack(config, "SRE", sre_name=sre_name)
                if stack.work_dir.exists():
                    stack.teardown()
                else:
                    raise DataSafeHavenInputException(
                        f"SRE {sre_name} not found - check the name is spelt correctly."
                    )
            except Exception as exc:
                raise DataSafeHavenInputException(
                    f"Unable to teardown Pulumi infrastructure.\n{str(exc)}"
                ) from exc

            # Remove information from config file
            if stack.stack_name in config.pulumi.stacks.keys():
                del config.pulumi.stacks[stack.stack_name]
            if sre_name in config.sre.keys():
                del config.sre[sre_name]

            # Upload config to blob storage
            config.upload()
        except DataSafeHavenException as exc:
            raise DataSafeHavenException(
                f"Could not teardown Data Safe Haven '{environment_name}'.\n{str(exc)}"
            ) from exc
