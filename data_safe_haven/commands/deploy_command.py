"""Command-line application for deploying a Data Safe Haven component, delegating the details to a subcommand"""
# Local imports
from .base_command import CommandGroup
from .deploy_shm_command import DeploySHMCommand
from .deploy_sre_command import DeploySRECommand


class DeployCommand(CommandGroup):
    """Deploy a Data Safe Haven component, delegating the details to a subcommand"""

    def __init__(self):
        super().__init__()
        self.subcommand(
            DeploySHMCommand,
            name="shm",
            help="Deploy a Safe Haven Management component.",
        )
        self.subcommand(
            DeploySRECommand,
            name="sre",
            help="Deploy a Safe Haven Management component.",
        )
