"""Command-line application for managing users for a Data Safe Haven deployment, delegating the details to a subcommand"""
# Third party imports
from cleo import Command

# Local imports
from .users_list import UsersListCommand


class UsersCommand(Command):
    """
    User management for a Data Safe Haven deployment, delegating the details to a subcommand

    users
    """

    commands = [UsersListCommand()]
