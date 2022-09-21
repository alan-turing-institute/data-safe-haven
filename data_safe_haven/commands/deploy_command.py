"""Command-line application for deploying a Data Safe Haven component, delegating the details to a subcommand"""
# Third party imports
from cleo import Command

# Local imports
from .deploy_shm_command import DeploySHMCommand
from .deploy_sre_command import DeploySRECommand


class DeployCommand(Command):
    """
    Deploy a Data Safe Haven component, delegating the details to a subcommand

    deploy
    """

    commands = [DeploySHMCommand(), DeploySRECommand()]
