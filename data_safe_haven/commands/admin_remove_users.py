"""Remove existing users from a deployed Data Safe Haven"""

from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config, ContextSettings
from data_safe_haven.exceptions import DataSafeHavenError
from data_safe_haven.external import GraphApi


def admin_remove_users(
    usernames: list[str],
) -> None:
    """Remove existing users from a deployed Data Safe Haven"""
    context = ContextSettings.from_file().assert_context()
    config = Config.from_remote(context)

    shm_name = context.shm_name

    try:
        # Load GraphAPI
        graph_api = GraphApi(
            tenant_id=config.shm.aad_tenant_id,
            default_scopes=["User.ReadWrite.All"],
        )

        # Remove users from SHM
        if usernames:
            users = UserHandler(config, graph_api)
            users.remove(usernames)
    except DataSafeHavenError as exc:
        msg = f"Could not remove users from Data Safe Haven '{shm_name}'.\n{exc}"
        raise DataSafeHavenError(msg) from exc
