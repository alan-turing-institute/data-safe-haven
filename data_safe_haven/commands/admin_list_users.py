"""List users from a deployed Data Safe Haven"""

from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config, DSHPulumiConfig
from data_safe_haven.context import ContextSettings
from data_safe_haven.exceptions import DataSafeHavenError
from data_safe_haven.external import GraphApi


def admin_list_users() -> None:
    """List users from a deployed Data Safe Haven"""
    context = ContextSettings.from_file().assert_context()
    config = Config.from_remote(context)
    pulumi_config = DSHPulumiConfig.from_remote(context)

    shm_name = context.shm_name

    try:
        # Load GraphAPI
        graph_api = GraphApi(
            tenant_id=config.shm.entra_id_tenant_id,
            default_scopes=["Directory.Read.All", "Group.Read.All"],
        )

        # List users from all sources
        users = UserHandler(context, config, pulumi_config, graph_api)
        users.list()
    except DataSafeHavenError as exc:
        msg = f"Could not list users for Data Safe Haven '{shm_name}'.\n{exc}"
        raise DataSafeHavenError(msg) from exc
