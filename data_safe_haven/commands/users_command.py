"""Command-line application for managing users for a Data Safe Haven deployment, delegating the details to a subcommand"""
# Third party imports
from cleo import Command

# Local imports
from .users_add import UsersAddCommand
from .users_list import UsersListCommand
from .users_register import UsersRegisterCommand
from .users_remove import UsersRemoveCommand
from .users_unregister import UsersUnregisterCommand


class UsersCommand(Command):  # type: ignore
    """
    User management for a Data Safe Haven deployment, delegating the details to a subcommand

    users
    """

    commands = [
        UsersAddCommand(),
        UsersListCommand(),
        UsersRegisterCommand(),
        UsersRemoveCommand(),
        UsersUnregisterCommand(),
    ]
