"""Command-line application for performing user management tasks."""

import pathlib
from typing import Annotated

import typer

from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import DSHPulumiConfig, SHMConfig, SREConfig
from data_safe_haven.context import ContextSettings
from data_safe_haven.exceptions import DataSafeHavenError
from data_safe_haven.external import GraphApi
from data_safe_haven.logging import get_logger

users_command_group = typer.Typer()


@users_command_group.command()
def add(
    csv: Annotated[
        pathlib.Path,
        typer.Argument(
            help="A CSV file containing details of users to add.",
        ),
    ],
) -> None:
    """Add users to a deployed Data Safe Haven."""
    context = ContextSettings.from_file().assert_context()
    shm_config = SHMConfig.from_remote(context)
    pulumi_config = DSHPulumiConfig.from_remote(context)

    shm_name = context.shm_name

    logger = get_logger()
    if shm_name not in pulumi_config.project_names:
        logger.fatal(f"No Pulumi project for '{shm_name}'.\nHave you deployed the SHM?")
        raise typer.Exit(1)

    try:
        # Load GraphAPI
        graph_api = GraphApi(
            tenant_id=shm_config.shm.entra_tenant_id,
            default_scopes=[
                "Group.Read.All",
                "User.ReadWrite.All",
                "UserAuthenticationMethod.ReadWrite.All",
            ],
        )

        # Add users to SHM
        users = UserHandler(context, pulumi_config, graph_api)
        users.add(csv)
    except DataSafeHavenError as exc:
        logger.critical(f"Could not add users to Data Safe Haven '{shm_name}'.")
        raise typer.Exit(1) from exc


@users_command_group.command("list")
def list_users(
    sre: Annotated[
        str,
        typer.Argument(
            help="The name of the SRE to list users from.",
        ),
    ],
) -> None:
    """List users from a deployed Data Safe Haven."""
    context = ContextSettings.from_file().assert_context()
    shm_config = SHMConfig.from_remote(context)
    pulumi_config = DSHPulumiConfig.from_remote(context)

    shm_name = context.shm_name

    logger = get_logger()
    if shm_name not in pulumi_config.project_names:
        logger.fatal(f"No Pulumi project for '{shm_name}'.\nHave you deployed the SHM?")
        raise typer.Exit(1)

    try:
        # Load GraphAPI
        graph_api = GraphApi(
            tenant_id=shm_config.shm.entra_tenant_id,
            default_scopes=["Directory.Read.All", "Group.Read.All"],
        )

        # List users from all sources
        users = UserHandler(context, pulumi_config, graph_api)
        users.list(sre)
    except DataSafeHavenError as exc:
        logger.critical(f"Could not list users for Data Safe Haven '{shm_name}'.")
        raise typer.Exit(1) from exc


@users_command_group.command()
def register(
    usernames: Annotated[
        list[str],
        typer.Option(
            "--username",
            "-u",
            help="Username of a user to register with this SRE. [*may be specified several times*]",
        ),
    ],
    sre: Annotated[
        str,
        typer.Argument(
            help="The name of the SRE to add the users to.",
        ),
    ],
) -> None:
    """Register existing users with a deployed SRE."""
    context = ContextSettings.from_file().assert_context()
    pulumi_config = DSHPulumiConfig.from_remote(context)
    shm_config = SHMConfig.from_remote(context)
    sre_config = SREConfig.from_remote_by_name(context, sre)

    shm_name = context.shm_name
    sre_name = sre_config.safe_name

    logger = get_logger()
    if shm_name not in pulumi_config.project_names:
        logger.critical(
            f"No Pulumi project for '{shm_name}'.\nHave you deployed the SHM?"
        )
        raise typer.Exit(1)

    if sre_name not in pulumi_config.project_names:
        logger.critical(
            f"No Pulumi project for '{sre_name}'.\nHave you deployed the SRE?"
        )
        raise typer.Exit(1)

    try:
        logger.debug(
            f"Preparing to register {len(usernames)} user(s) with SRE '{sre_name}'"
        )

        # Load GraphAPI
        graph_api = GraphApi(
            tenant_id=shm_config.shm.entra_tenant_id,
            default_scopes=["Group.ReadWrite.All", "GroupMember.ReadWrite.All"],
        )

        # List users
        users = UserHandler(context, pulumi_config, graph_api)
        available_usernames = users.get_usernames_entra_id()
        usernames_to_register = []
        for username in usernames:
            if username in available_usernames:
                usernames_to_register.append(username)
            else:
                logger.error(
                    f"Username '{username}' does not belong to this Data Safe Haven deployment."
                    " Please use 'dsh users add' to create it."
                )
        users.register(sre_name, usernames_to_register)
    except DataSafeHavenError as exc:
        logger.critical(
            f"Could not register users from Data Safe Haven '{shm_name}' with SRE '{sre_name}'."
        )
        raise typer.Exit(1) from exc


@users_command_group.command()
def remove(
    usernames: Annotated[
        list[str],
        typer.Option(
            "--username",
            "-u",
            help="Username of a user to remove from this Data Safe Haven. [*may be specified several times*]",
        ),
    ],
) -> None:
    """Remove existing users from a deployed Data Safe Haven."""
    context = ContextSettings.from_file().assert_context()
    pulumi_config = DSHPulumiConfig.from_remote(context)
    shm_config = SHMConfig.from_remote(context)

    shm_name = context.shm_name

    logger = get_logger()
    if shm_name not in pulumi_config.project_names:
        logger.fatal(f"No Pulumi project for '{shm_name}'.\nHave you deployed the SHM?")
        raise typer.Exit(1)

    try:
        # Load GraphAPI
        graph_api = GraphApi(
            tenant_id=shm_config.shm.entra_tenant_id,
            default_scopes=["User.ReadWrite.All"],
        )

        # Remove users from SHM
        if usernames:
            users = UserHandler(context, pulumi_config, graph_api)
            users.remove(usernames)
    except DataSafeHavenError as exc:
        logger.critical(f"Could not remove users from Data Safe Haven '{shm_name}'.")
        raise typer.Exit(1) from exc


@users_command_group.command()
def unregister(
    usernames: Annotated[
        list[str],
        typer.Option(
            "--username",
            "-u",
            help="Username of a user to unregister from this SRE. [*may be specified several times*]",
        ),
    ],
    sre: Annotated[
        str,
        typer.Argument(
            help="The name of the SRE to unregister the users from.",
        ),
    ],
) -> None:
    """Unregister existing users from a deployed SRE."""
    context = ContextSettings.from_file().assert_context()
    pulumi_config = DSHPulumiConfig.from_remote(context)
    shm_config = SHMConfig.from_remote(context)
    sre_config = SREConfig.from_remote_by_name(context, sre)

    shm_name = context.shm_name
    sre_name = sre_config.safe_name

    logger = get_logger()
    if shm_name not in pulumi_config.project_names:
        logger.fatal(f"No Pulumi project for '{shm_name}'.\nHave you deployed the SHM?")
        raise typer.Exit(1)

    if sre_name not in pulumi_config.project_names:
        logger.fatal(f"No Pulumi project for '{sre_name}'.\nHave you deployed the SRE?")
        raise typer.Exit(1)

    try:
        logger.debug(
            f"Preparing to unregister {len(usernames)} users with SRE '{sre_name}'"
        )

        # Load GraphAPI
        graph_api = GraphApi(
            tenant_id=shm_config.shm.entra_tenant_id,
            default_scopes=["Group.ReadWrite.All", "GroupMember.ReadWrite.All"],
        )

        # List users
        users = UserHandler(context, pulumi_config, graph_api)
        available_usernames = users.get_usernames_entra_id()
        usernames_to_unregister = []
        for username in usernames:
            if username in available_usernames:
                usernames_to_unregister.append(username)
            else:
                logger.error(
                    f"Username '{username}' does not belong to this Data Safe Haven deployment."
                    " Please use 'dsh users add' to create it."
                )
        for group_name in (
            f"{sre_name} Users",
            f"{sre_name} Privileged Users",
            f"{sre_name} Administrators",
        ):
            users.unregister(group_name, usernames_to_unregister)
    except DataSafeHavenError as exc:
        logger.critical(
            f"Could not unregister users from Data Safe Haven '{shm_name}' with SRE '{sre_name}'."
        )
        raise typer.Exit(1) from exc
