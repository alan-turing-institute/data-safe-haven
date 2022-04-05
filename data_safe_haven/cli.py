"""Command line entrypoint for Data Safe Haven application"""
# Third party imports
from cleo import Application

# Local imports
from data_safe_haven import __version__
from data_safe_haven.commands import AdminCommand, DeployCommand, InitialiseCommand

application = Application("dsh", __version__, complete=True)
application.add(AdminCommand())
application.add(DeployCommand())
application.add(InitialiseCommand())


def main():
    """Command line entrypoint for Data Safe Haven application"""
    application.run()
