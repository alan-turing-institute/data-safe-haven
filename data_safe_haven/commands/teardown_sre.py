"""Teardown a deployed Secure Research Environment"""
from data_safe_haven.config import Config
from data_safe_haven.exceptions import (
    DataSafeHavenError,
    DataSafeHavenInputError,
)
from data_safe_haven.external import GraphApi
from data_safe_haven.functions import alphanumeric
from data_safe_haven.infrastructure import SREStackManager


def teardown_sre(name: str) -> None:
    """Teardown a deployed Secure Research Environment"""
    sre_name = "UNKNOWN"
    try:
        # Use a JSON-safe SRE name
        sre_name = alphanumeric(name).lower()

        # Load config file
        config = Config()

        # Load GraphAPI as this may require user-interaction that is not possible as
        # part of a Pulumi declarative command
        graph_api = GraphApi(
            tenant_id=config.shm.aad_tenant_id,
            default_scopes=["Application.ReadWrite.All", "Group.ReadWrite.All"],
        )

        # Remove infrastructure deployed with Pulumi
        try:
            stack = SREStackManager(config, sre_name, graph_api_token=graph_api.token)
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
