"""Command-line application for tearing down a Data Safe Haven component, delegating the details to a subcommand"""
# Local imports
from .base_command import CommandGroup
from .teardown_backend_command import TeardownBackendCommand
from .teardown_shm_command import TeardownSHMCommand
from .teardown_sre_command import TeardownSRECommand


class TeardownCommand(CommandGroup):
    """Tear down a Data Safe Haven component, delegating the details to a subcommand"""

    def __init__(self):
        super().__init__()
        # Register commands
        self.subcommand(
            TeardownBackendCommand,
            name="backend",
            help="Tear down a deployed Data Safe Haven backend.",
        )
        self.subcommand(
            TeardownSHMCommand,
            name="shm",
            help="Tear down a deployed a Safe Haven Management component.",
        )
        self.subcommand(
            TeardownSRECommand,
            name="sre",
            help="Tear down a deployed a Secure Research Environment component.",
        )
