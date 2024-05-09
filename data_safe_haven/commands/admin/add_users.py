import pathlib
from typing import Annotated

import typer

from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config, DSHPulumiConfig
from data_safe_haven.context import ContextSettings
from data_safe_haven.exceptions import DataSafeHavenError
from data_safe_haven.external import GraphApi

from . import admin_command_group


@admin_command_group.command(help="Add users to a deployed Data Safe Haven.")
def add_users(
    csv: Annotated[
        pathlib.Path,
        typer.Argument(
            help="A CSV file containing details of users to add.",
        ),
    ],
) -> None:
    """Add users to a deployed Data Safe Haven"""
    context = ContextSettings.from_file().assert_context()
    config = Config.from_remote(context)
    pulumi_config = DSHPulumiConfig.from_remote(context)

    shm_name = context.shm_name

    try:
        # Load GraphAPI
        graph_api = GraphApi(
            tenant_id=config.shm.entra_tenant_id,
            default_scopes=[
                "Group.Read.All",
                "User.ReadWrite.All",
                "UserAuthenticationMethod.ReadWrite.All",
            ],
        )

        # Add users to SHM
        users = UserHandler(context, config, pulumi_config, graph_api)
        users.add(csv)
    except DataSafeHavenError as exc:
        msg = f"Could not add users to Data Safe Haven '{shm_name}'.\n{exc}"
        raise DataSafeHavenError(msg) from exc
