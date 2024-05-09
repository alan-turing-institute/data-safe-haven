from typing import Annotated

import typer

from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config, DSHPulumiConfig
from data_safe_haven.context import ContextSettings
from data_safe_haven.exceptions import DataSafeHavenError
from data_safe_haven.external import GraphApi

from . import admin_command_group


@admin_command_group.command(
    help="Remove existing users from a deployed Data Safe Haven."
)
def remove_users(
    usernames: Annotated[
        list[str],
        typer.Option(
            "--username",
            "-u",
            help="Username of a user to remove from this Data Safe Haven. [*may be specified several times*]",
        ),
    ],
) -> None:
    """Remove existing users from a deployed Data Safe Haven"""
    context = ContextSettings.from_file().assert_context()
    config = Config.from_remote(context)
    pulumi_config = DSHPulumiConfig.from_remote(context)

    shm_name = context.shm_name

    try:
        # Load GraphAPI
        graph_api = GraphApi(
            tenant_id=config.shm.entra_tenant_id,
            default_scopes=["User.ReadWrite.All"],
        )

        # Remove users from SHM
        if usernames:
            users = UserHandler(context, config, pulumi_config, graph_api)
            users.remove(usernames)
    except DataSafeHavenError as exc:
        msg = f"Could not remove users from Data Safe Haven '{shm_name}'.\n{exc}"
        raise DataSafeHavenError(msg) from exc
