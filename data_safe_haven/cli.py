"""Command line entrypoint for Data Safe Haven application"""
# Third party imports
from cleo import Application

# Local imports
from data_safe_haven import __version__
from data_safe_haven.commands import (
    DeployCommand,
    InitialiseCommand,
    TeardownCommand,
    UsersCommand,
)

application = Application("dsh", __version__, complete=True)
application.add(DeployCommand())
application.add(InitialiseCommand())
application.add(TeardownCommand())
application.add(UsersCommand())


def main() -> int:
    """Command line entrypoint for Data Safe Haven application"""
    return application.run()  # type: ignore
