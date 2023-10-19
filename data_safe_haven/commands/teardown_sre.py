"""Teardown a deployed Secure Research Environment"""
from data_safe_haven.config import Config
from data_safe_haven.exceptions import (
    DataSafeHavenError,
    DataSafeHavenInputError,
)
from data_safe_haven.functions import alphanumeric
from data_safe_haven.infrastructure import PulumiAccount, SREStackManager


def teardown_sre(name: str) -> None:
    """Teardown a deployed Secure Research Environment"""
    sre_name = "UNKNOWN"
    try:
        # Use a JSON-safe SRE name
        sre_name = alphanumeric(name).lower()

        # Load config file
        config = Config()

        # Remove infrastructure deployed with Pulumi
        try:
            PulumiAccount(config).handle_login()
            stack = SREStackManager(config, sre_name)
            if stack.work_dir.exists():
                stack.teardown()
            else:
                msg = f"SRE {sre_name} not found - check the name is spelt correctly."
                raise DataSafeHavenInputError(msg)
        except Exception as exc:
            msg = f"Unable to teardown Pulumi infrastructure.\n{exc}"
            raise DataSafeHavenInputError(msg) from exc

        # Remove information from config file
        config.remove_stack(stack.stack_name)
        config.remove_sre(sre_name)

        # Upload config to blob storage
        config.upload()
    except DataSafeHavenError as exc:
        msg = f"Could not teardown Secure Research Environment '{sre_name}'.\n{exc}"
        raise DataSafeHavenError(msg) from exc
