"""Command-line application for performing administrative tasks for a Data Safe Haven deployment, delegating the details to a subcommand"""
# Standard library imports
import pathlib
from typing import Annotated, List

# Third party imports
import typer

# Local imports
from .users_add_command import UsersAddCommand
from .users_list_command import UsersListCommand
from .users_register_command import UsersRegisterCommand
from .users_remove_command import UsersRemoveCommand
from .users_unregister_command import UsersUnregisterCommand

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
    UsersAddCommand()(csv)


@admin_command_group.command(help="List users from a deployed Data Safe Haven.")
def list_users() -> None:
    UsersListCommand()()


@admin_command_group.command(
    help="Register existing users with a deployed Secure Research Environment."
)
def register_users(
    usernames: Annotated[
        List[str],
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
    UsersRegisterCommand()(usernames, sre)


@admin_command_group.command(
    help="Remove existing users from a deployed Data Safe Haven."
)
def remove_users(
    usernames: Annotated[
        List[str],
        typer.Option(
            "--username",
            "-u",
            help="Username of a user to remove from this Data Safe Haven. [*may be specified several times*]",
        ),
    ],
) -> None:
    UsersRemoveCommand()(usernames)


@admin_command_group.command(help="Unregister existing users from a deployed SRE.")
def unregister_users(
    usernames: Annotated[
        List[str],
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
    UsersUnregisterCommand()(usernames, sre)
