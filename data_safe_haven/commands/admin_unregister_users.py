"""Unregister existing users from a deployed SRE"""

from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config, ContextSettings
from data_safe_haven.exceptions import DataSafeHavenError
from data_safe_haven.external import GraphApi
from data_safe_haven.utility import LoggingSingleton


def admin_unregister_users(
    usernames: list[str],
    sre: str,
) -> None:
    """Unregister existing users from a deployed SRE"""
    context = ContextSettings.from_file().assert_context()
    config = Config.from_remote(context)

    shm_name = context.shm_name
    sre_name = config.sanitise_sre_name(sre)

    try:
        # Check that SRE option has been provided
        if not sre_name:
            msg = "SRE name must be specified."
            raise DataSafeHavenError(msg)
        LoggingSingleton().info(
            f"Preparing to unregister {len(usernames)} users with SRE '{sre_name}'"
        )

        # Load GraphAPI as this may require user-interaction that is not
        # possible as part of a Pulumi declarative command
        graph_api = GraphApi(
            tenant_id=config.shm.aad_tenant_id,
            default_scopes=["Group.Read.All"],
        )

        # List users
        users = UserHandler(config, graph_api)
        available_usernames = users.get_usernames_domain_controller()
        usernames_to_unregister = []
        for username in usernames:
            if username in available_usernames:
                usernames_to_unregister.append(username)
            else:
                LoggingSingleton().error(
                    f"Username '{username}' does not belong to this Data Safe Haven deployment."
                    " Please use 'dsh users add' to create it."
                )
        users.unregister(sre_name, usernames_to_unregister)
    except DataSafeHavenError as exc:
        msg = f"Could not unregister users from Data Safe Haven '{shm_name}' with SRE '{sre_name}'.\n{exc}"
        raise DataSafeHavenError(msg) from exc
