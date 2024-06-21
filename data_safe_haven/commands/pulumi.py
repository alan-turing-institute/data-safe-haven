"""Interact with the Pulumi CLI using DSH projects"""

from enum import UNIQUE, StrEnum, auto, verify
from typing import Annotated

import typer
from rich import print as rprint

from data_safe_haven.config import DSHPulumiConfig, SHMConfig, SREConfig
from data_safe_haven.context import ContextSettings
from data_safe_haven.external import GraphApi
from data_safe_haven.infrastructure import SHMProjectManager, SREProjectManager
from data_safe_haven.logging import get_logger

pulumi_command_group = typer.Typer()


@verify(UNIQUE)
class ProjectType(StrEnum):
    SHM = auto()
    SRE = auto()


@pulumi_command_group.command()
def run(
    project_type: Annotated[
        ProjectType,
        typer.Argument(help="DSH project type, SHM or SRE"),
    ],
    command: Annotated[
        str,
        typer.Argument(help="Pulumi command to run, e.g. refresh"),
    ],
    sre_name: Annotated[
        str,
        typer.Option(help="SRE name"),
    ] = "",
) -> None:
    """Run arbitrary Pulumi commands in a DSH project"""
    logger = get_logger()
    if project_type == ProjectType.SRE and not sre_name:
        logger.fatal("--sre-name is required.")
        raise typer.Exit(1)

    context = ContextSettings.from_file().assert_context()
    pulumi_config = DSHPulumiConfig.from_remote(context)
    shm_config = SHMConfig.from_remote(context)

    # This is needed to avoid linting errors from mypy
    project: SHMProjectManager | SREProjectManager

    if project_type == ProjectType.SHM:
        project = SHMProjectManager(
            context=context,
            config=shm_config,
            pulumi_config=pulumi_config,
        )
    elif project_type == ProjectType.SRE:
        sre_config = SREConfig.from_remote_by_name(context, sre_name)

        graph_api = GraphApi(
            tenant_id=shm_config.shm.entra_tenant_id,
            default_scopes=[
                "Application.ReadWrite.All",
                "AppRoleAssignment.ReadWrite.All",
                "Directory.ReadWrite.All",
                "Group.ReadWrite.All",
            ],
        )

        project = SREProjectManager(
            context=context,
            config=sre_config,
            pulumi_config=pulumi_config,
            sre_name=sre_config.safe_name,
            graph_api_token=graph_api.token,
        )

    stdout = project.run_pulumi_command(command)
    rprint(stdout)
