"""Teardown a deployed a Safe Haven Management component"""
from data_safe_haven.config import Config
from data_safe_haven.exceptions import (
    DataSafeHavenError,
    DataSafeHavenInputError,
)
from data_safe_haven.infrastructure import SHMStackManager


def teardown_shm() -> None:
    """Teardown a deployed a Safe Haven Management component"""
    try:
        # Load config file
        config = Config()

        # Remove infrastructure deployed with Pulumi
        try:
            stack = SHMStackManager(config)
            stack.teardown()
        except Exception as exc:
            msg = f"Unable to teardown Pulumi infrastructure.\n{exc}"
            raise DataSafeHavenInputError(msg) from exc

        # Remove information from config file
        if stack.stack_name in config.pulumi.stacks.keys():
            del config.pulumi.stacks[stack.stack_name]

        # Upload config to blob storage
        config.upload()
    except DataSafeHavenError as exc:
        msg = f"Could not teardown Safe Haven Management component.\n{exc}"
        raise DataSafeHavenError(msg) from exc
