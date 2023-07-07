"""Command-line application for managing users for a Data Safe Haven deployment, delegating the details to a subcommand"""
# Local imports
from .base_command import CommandGroup
from .users_add_command import UsersAddCommand
from .users_list_command import UsersListCommand
from .users_register_command import UsersRegisterCommand
from .users_remove_command import UsersRemoveCommand
from .users_unregister_command import UsersUnregisterCommand


class UsersCommand(CommandGroup):
    """Manage users for a Data Safe Haven deployment, delegating the details to a subcommand"""

    def __init__(self):
        super().__init__()
        # Register commands
        self.subcommand(
            UsersAddCommand, name="add", help="Add users to a deployed Data Safe Haven."
        )
        self.subcommand(
            UsersListCommand,
            name="list",
            help="List users from a deployed Data Safe Haven.",
        )
        self.subcommand(
            UsersRegisterCommand,
            name="register",
            help="Register existing users with a deployed SRE.",
        )
        self.subcommand(
            UsersRemoveCommand,
            name="remove",
            help="Remove existing users from a deployed Data Safe Haven.",
        )
        self.subcommand(
            UsersUnregisterCommand,
            name="unregister",
            help="Unregister existing users from a deployed SRE.",
        )
