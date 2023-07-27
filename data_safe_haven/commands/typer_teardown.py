"""Command-line application for tearing down a Data Safe Haven component, delegating the details to a subcommand"""
from typing import Annotated

import typer

from .teardown_backend_command import TeardownBackendCommand
from .teardown_shm_command import TeardownSHMCommand
from .teardown_sre_command import TeardownSRECommand

teardown_command_group = typer.Typer()


@teardown_command_group.command(help="Tear down a deployed Data Safe Haven backend.")  # type: ignore [misc]
def backend() -> None:
    TeardownBackendCommand()()


@teardown_command_group.command(
    help="Tear down a deployed a Safe Haven Management component."
)  # type: ignore [misc]
def shm() -> None:
    TeardownSHMCommand()()


@teardown_command_group.command(
    help="Tear down a deployed a Secure Research Environment component."
)  # type: ignore [misc]
def sre(
    name: Annotated[str, typer.Argument(help="Name of SRE to teardown.")],
) -> None:
    TeardownSRECommand()(name)
