"""Interact with the Pulumi CLI using DSH projects"""

from enum import UNIQUE, StrEnum, auto, verify
from typing import Annotated

import typer

from data_safe_haven import console
from data_safe_haven.config import ContextManager, DSHPulumiConfig, SREConfig
from data_safe_haven.infrastructure import SREProjectManager

pulumi_command_group = typer.Typer()


@verify(UNIQUE)
class ProjectType(StrEnum):
    SHM = auto()
    SRE = auto()


@pulumi_command_group.command()
def run(
    sre_name: Annotated[
        str,
        typer.Argument(help="SRE name"),
    ],
    command: Annotated[
        str,
        typer.Argument(help="Pulumi command to run, e.g. refresh"),
    ],
) -> None:
    """Run arbitrary Pulumi commands in a DSH project"""
    context = ContextManager.from_file().assert_context()
    pulumi_config = DSHPulumiConfig.from_remote(context)
    sre_config = SREConfig.from_remote_by_name(context, sre_name)

    project = SREProjectManager(
        context=context,
        config=sre_config,
        pulumi_config=pulumi_config,
    )

    stdout = project.run_pulumi_command(command)
    console.print(stdout)
