"""List users from a deployed Data Safe Haven"""
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config
from data_safe_haven.exceptions import DataSafeHavenError
from data_safe_haven.external import GraphApi


def admin_list_users() -> None:
    """List users from a deployed Data Safe Haven"""
    shm_name = "UNKNOWN"
    try:
        # Load config file
        config = Config()
        shm_name = config.context.name

        # Load GraphAPI as this may require user-interaction that is not
        # possible as part of a Pulumi declarative command
        graph_api = GraphApi(
            tenant_id=config.shm.aad_tenant_id,
            default_scopes=["Directory.Read.All", "Group.Read.All"],
        )

        # List users from all sources
        users = UserHandler(config, graph_api)
        users.list()
    except DataSafeHavenError as exc:
        msg = f"Could not list users for Data Safe Haven '{shm_name}'.\n{exc}"
        raise DataSafeHavenError(msg) from exc