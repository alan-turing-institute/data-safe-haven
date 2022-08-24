"""Command line entrypoint for Data Safe Haven application"""
# Third party imports
from cleo import Application

# Local imports
from data_safe_haven import __version__
from data_safe_haven.commands import (
    DeploySRECommand,
    InitialiseCommand,
    UsersCommand,
    TeardownCommand,
)

application = Application("dsh", __version__, complete=True)
application.add(DeploySRECommand())
application.add(InitialiseCommand())
application.add(TeardownCommand())
application.add(UsersCommand())


def main():
    """Command line entrypoint for Data Safe Haven application"""
    application.run()
