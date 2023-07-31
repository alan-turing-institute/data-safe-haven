"""Command-line application for tearing down a Data Safe Haven component, delegating the details to a subcommand"""
from typing import Annotated

import typer

from .teardown_backend import teardown_backend
from .teardown_shm import teardown_shm
from .teardown_sre import teardown_sre

teardown_command_group = typer.Typer()


@teardown_command_group.command(help="Tear down a deployed Data Safe Haven backend.")
def backend() -> None:
    teardown_backend()


@teardown_command_group.command(
    help="Tear down a deployed a Safe Haven Management component."
)
def shm() -> None:
    teardown_shm()


@teardown_command_group.command(
    help="Tear down a deployed a Secure Research Environment component."
)
def sre(
    name: Annotated[str, typer.Argument(help="Name of SRE to teardown.")],
) -> None:
    teardown_sre(name)
