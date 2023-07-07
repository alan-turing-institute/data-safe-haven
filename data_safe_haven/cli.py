"""Command line entrypoint for Data Safe Haven application"""
# Standard library imports
import pathlib
from typing import Optional

# Third party imports
import typer
from typing_extensions import Annotated

# Local imports
from data_safe_haven import __version__
from data_safe_haven.commands import (
    AdminCommand,
    DeployCommand,
    InitialiseCommand,
    TeardownCommand,
)
from data_safe_haven.exceptions import DataSafeHavenException
from data_safe_haven.utility import Logger


def callback(
    output: Annotated[
        Optional[pathlib.Path],
        typer.Option(
            "--output", "-o", resolve_path=True, help="Path to an output log file"
        ),
    ] = None,
    verbosity: Annotated[
        Optional[int],
        typer.Option(
            "--verbosity",
            "-v",
            help="Increase the verbosity of messages: each '-v' will increase by one step.",
            count=True,
            is_eager=True,
        ),
    ] = None,
    version: Annotated[
        Optional[bool],
        typer.Option(
            "--version", "-V", help="Display the version of this application."
        ),
    ] = None,
):
    """Arguments to the main executable"""
    Logger(verbosity, output)  # initialise logging singleton
    if version:
        print(f"Data Safe Haven {__version__}")
        raise typer.Exit()


def main() -> None:
    """Command line entrypoint for Data Safe Haven application"""

    # Create the application
    application = typer.Typer(
        context_settings={"help_option_names": ["-h", "--help"]},
        invoke_without_command=True,
        no_args_is_help=True,
    )

    # Register arguments to the main executable
    application.callback()(callback)

    # Register command groups
    application.add_typer(
        AdminCommand(),
        name="admin",
        help="Perform administrative tasks on a deployed Data Safe Haven.",
    )
    application.add_typer(
        DeployCommand(), name="deploy", help="Deploy a Data Safe Haven component."
    )
    application.add_typer(
        TeardownCommand(),
        name="teardown",
        help="Tear down a Data Safe Haven component.",
    )

    # Register direct subcommands
    application.command(name="init", help="Initialise a Data Safe Haven deployment.")(
        InitialiseCommand().entrypoint
    )

    # Start the application
    try:
        application()
    except DataSafeHavenException as exc:
        logger = Logger()
        for line in str(exc).split("\n"):
            logger.error(line)
