"""Command-line application for performing user management tasks."""

import pathlib
from typing import Annotated

import typer

from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import ContextManager, DSHPulumiConfig, SHMConfig, SREConfig
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
    logger = get_logger()
    try:
        context = ContextManager.from_file().assert_context()

        # Load SHMConfig
        try:
            shm_config = SHMConfig.from_remote(context)
        except DataSafeHavenError:
            logger.error("Have you deployed the SHM?")
            raise

        # Load GraphAPI
        graph_api = GraphApi.from_scopes(
            scopes=[
                "Group.Read.All",
                "User.ReadWrite.All",
                "UserAuthenticationMethod.ReadWrite.All",
            ],
            tenant_id=shm_config.shm.entra_tenant_id,
        )

        # Add users to SHM
        users = UserHandler(context, graph_api)
        users.add(csv, shm_config.shm.fqdn)
    except DataSafeHavenError as exc:
        logger.critical("Could not add users to Data Safe Haven.")
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
    logger = get_logger()
    try:
        context = ContextManager.from_file().assert_context()

        # Load SHMConfig
        try:
            shm_config = SHMConfig.from_remote(context)
        except DataSafeHavenError:
            logger.error("Have you deployed the SHM?")
            raise

        # Load GraphAPI
        graph_api = GraphApi.from_scopes(
            scopes=["Directory.Read.All", "Group.Read.All"],
            tenant_id=shm_config.shm.entra_tenant_id,
        )

        # Load Pulumi config
        pulumi_config = DSHPulumiConfig.from_remote(context)

        if sre not in pulumi_config.project_names:
            msg = f"Could not load Pulumi settings for '{sre}'. Is the SRE deployed?"
            logger.error(msg)
            raise typer.Exit(1)
        # List users from all sources
        users = UserHandler(context, graph_api)
        users.list(sre, pulumi_config)
    except DataSafeHavenError as exc:
        logger.critical("Could not list Data Safe Haven users.")
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
    logger = get_logger()
    try:
        context = ContextManager.from_file().assert_context()

        # Load SHMConfig
        try:
            shm_config = SHMConfig.from_remote(context)
        except DataSafeHavenError:
            logger.error("Have you deployed the SHM?")
            raise

        # Load Pulumi config
        pulumi_config = DSHPulumiConfig.from_remote(context)

        # Load SREConfig
        sre_config = SREConfig.from_remote_by_name(context, sre)
        if sre_config.name not in pulumi_config.project_names:
            msg = f"Could not load Pulumi settings for '{sre_config.name}'. Have you deployed the SRE?"
            logger.error(msg)
            raise DataSafeHavenError(msg)

        # Load GraphAPI
        graph_api = GraphApi.from_scopes(
            scopes=["Group.ReadWrite.All", "GroupMember.ReadWrite.All"],
            tenant_id=shm_config.shm.entra_tenant_id,
        )

        logger.debug(
            f"Preparing to register {len(usernames)} user(s) with SRE '{sre_config.name}'"
        )

        # List users
        users = UserHandler(context, graph_api)
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
        users.register(sre_config.name, usernames_to_register)
    except DataSafeHavenError as exc:
        logger.critical(f"Could not register Data Safe Haven users with SRE '{sre}'.")
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
    logger = get_logger()
    try:
        context = ContextManager.from_file().assert_context()

        # Load SHMConfig
        try:
            shm_config = SHMConfig.from_remote(context)
        except DataSafeHavenError:
            logger.error("Have you deployed the SHM?")
            raise

        # Load GraphAPI
        graph_api = GraphApi.from_scopes(
            scopes=["User.ReadWrite.All"],
            tenant_id=shm_config.shm.entra_tenant_id,
        )

        # Remove users from SHM
        if usernames:
            users = UserHandler(context, graph_api)
            users.remove(usernames)
    except DataSafeHavenError as exc:
        logger.critical("Could not remove users from Data Safe Haven.")
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
    logger = get_logger()
    try:
        context = ContextManager.from_file().assert_context()

        # Load SHMConfig
        try:
            shm_config = SHMConfig.from_remote(context)
        except DataSafeHavenError:
            logger.error("Have you deployed the SHM?")
            raise

        # Load Pulumi config
        pulumi_config = DSHPulumiConfig.from_remote(context)

        # Load SREConfig
        sre_config = SREConfig.from_remote_by_name(context, sre)
        if sre_config.name not in pulumi_config.project_names:
            msg = f"Could not load Pulumi settings for '{sre_config.name}'. Have you deployed the SRE?"
            logger.error(msg)
            raise DataSafeHavenError(msg)

        # Load GraphAPI
        graph_api = GraphApi.from_scopes(
            scopes=["Group.ReadWrite.All", "GroupMember.ReadWrite.All"],
            tenant_id=shm_config.shm.entra_tenant_id,
        )

        logger.debug(
            f"Preparing to unregister {len(usernames)} users with SRE '{sre_config.name}'"
        )

        # List users
        users = UserHandler(context, graph_api)
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
            f"{sre_config.name} Users",
            f"{sre_config.name} Privileged Users",
            f"{sre_config.name} Administrators",
        ):
            users.unregister(group_name, usernames_to_unregister)
    except DataSafeHavenError as exc:
        logger.critical(f"Could not unregister Data Safe Haven users from SRE '{sre}'.")
        raise typer.Exit(1) from exc
