"""Command line entrypoint for Data Safe Haven application"""
from cleo import Application
from data_safe_haven.commands import DeployCommand, InitialiseCommand
from data_safe_haven import __version__

application = Application("dsh", __version__, complete=True)
application.add(InitialiseCommand())
application.add(DeployCommand())


def main():
    """Command line entrypoint for Data Safe Haven application"""
    application.run()
