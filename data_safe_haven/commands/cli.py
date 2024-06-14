"""Command line entrypoint for Data Safe Haven application"""

from typing import Annotated, Optional

import typer

from data_safe_haven import __version__
from data_safe_haven.exceptions import DataSafeHavenError
from data_safe_haven.utility import LoggingSingleton

from .config import config_command_group
from .context import context_command_group
from .pulumi import pulumi_command_group
from .shm import shm_command_group
from .sre import sre_command_group
from .users import users_command_group

# Create the application
application = typer.Typer(
    context_settings={"help_option_names": ["-h", "--help"]},
    invoke_without_command=True,
    name="dsh",
    no_args_is_help=True,
)


# Custom application callback
# This is executed before
@application.callback()
def callback(
    verbose: Annotated[
        bool,
        typer.Option(
            "--verbose",
            "-v",
            help="Increase the verbosity of console output.",
        ),
    ] = False,
    show_level: Annotated[
        bool,
        typer.Option(
            "--show-level",
            "-l",
            help="Show Log level.",
        ),
    ] = False,
    version: Annotated[
        Optional[bool],  # noqa: UP007
        typer.Option(
            "--version", "-V", help="Display the version of this application."
        ),
    ] = None,
) -> None:
    """Arguments to the main executable"""

    if verbose:
        LoggingSingleton.set_console_level("DEBUG")

    if show_level:
        LoggingSingleton.show_console_level()

    if version:
        print(f"Data Safe Haven {__version__}")  # noqa: T201
        raise typer.Exit()


# Register command groups
application.add_typer(
    users_command_group,
    name="users",
    help="Manage the users of a Data Safe Haven deployment.",
)
application.add_typer(
    config_command_group,
    name="config",
    help="Manage Data Safe Haven configuration.",
)
application.add_typer(
    context_command_group, name="context", help="Manage Data Safe Haven contexts."
)
application.add_typer(
    pulumi_command_group,
    name="pulumi",
    help="(Advanced) interact directly with the Pulumi CLI.",
)
application.add_typer(
    shm_command_group,
    name="shm",
    help="Manage Data Safe Haven SHM infrastructure.",
)
application.add_typer(
    sre_command_group,
    name="sre",
    help="Manage Data Safe Haven SRE infrastructure.",
)


def main() -> None:
    """Run the application and log any exceptions"""
    # application()
    try:
        application()
    except DataSafeHavenError as exc:
        logger = LoggingSingleton()
        for line in str(exc).split("\n"):
            logger.error(line)
