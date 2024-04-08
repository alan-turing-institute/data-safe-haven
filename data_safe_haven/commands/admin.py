"""Command-line application for performing administrative tasks"""

import pathlib
from typing import Annotated

import typer

from .admin_add_users import admin_add_users
from .admin_list_users import admin_list_users
from .admin_register_users import admin_register_users
from .admin_remove_users import admin_remove_users
from .admin_unregister_users import admin_unregister_users

admin_command_group = typer.Typer()


@admin_command_group.command(help="Add users to a deployed Data Safe Haven.")
def add_users(
    csv: Annotated[
        pathlib.Path,
        typer.Argument(
            help="A CSV file containing details of users to add.",
        ),
    ],
) -> None:
    admin_add_users(csv)


@admin_command_group.command(help="List users from a deployed Data Safe Haven.")
def list_users() -> None:
    admin_list_users()


@admin_command_group.command(
    help="Register existing users with a deployed Secure Research Environment."
)
def register_users(
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
    admin_register_users(usernames, sre)


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
    admin_remove_users(usernames)


@admin_command_group.command(help="Unregister existing users from a deployed SRE.")
def unregister_users(
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
    admin_unregister_users(usernames, sre)
