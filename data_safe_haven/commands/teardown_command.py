"""Command-line application for tearing down a Data Safe Haven component, delegating the details to a subcommand"""
# Third party imports
from cleo import Command

# Local imports
from .teardown_backend_command import TeardownBackendCommand
from .teardown_shm_command import TeardownSHMCommand
from .teardown_sre_command import TeardownSRECommand


class TeardownCommand(Command):
    """
    Tear down a Data Safe Haven component, delegating the details to a subcommand

    teardown
    """

    commands = [TeardownBackendCommand(), TeardownSHMCommand(), TeardownSRECommand()]
