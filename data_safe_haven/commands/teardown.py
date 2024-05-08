"""Command-line application for tearing down a Data Safe Haven component, delegating the details to a subcommand"""

from typing import Annotated

import typer

from data_safe_haven.config import Config, DSHPulumiConfig
from data_safe_haven.context import ContextSettings
from data_safe_haven.exceptions import (
    DataSafeHavenError,
    DataSafeHavenInputError,
)
from data_safe_haven.external import GraphApi
from data_safe_haven.functions import sanitise_sre_name
from data_safe_haven.infrastructure import SHMProjectManager, SREProjectManager

teardown_command_group = typer.Typer()


@teardown_command_group.command(
    help="Tear down a deployed a Safe Haven Management component."
)
def shm() -> None:
    context = ContextSettings.from_file().assert_context()
    config = Config.from_remote(context)
    pulumi_config = DSHPulumiConfig.from_remote(context)
    pulumi_project = pulumi_config[context.shm_name]

    try:
        # Remove infrastructure deployed with Pulumi
        try:
            stack = SHMProjectManager(context, config, pulumi_project)
            stack.teardown()
        except Exception as exc:
            msg = f"Unable to teardown Pulumi infrastructure.\n{exc}"
            raise DataSafeHavenInputError(msg) from exc

        # Remove information from config file
        del pulumi_config[context.shm_name]

        # Upload Pulumi config to blob storage
        pulumi_config.upload(context)
    except DataSafeHavenError as exc:
        msg = f"Could not teardown Safe Haven Management component.\n{exc}"
        raise DataSafeHavenError(msg) from exc


@teardown_command_group.command(
    help="Tear down a deployed a Secure Research Environment component."
)
def sre(
    name: Annotated[str, typer.Argument(help="Name of SRE to teardown.")],
) -> None:
    context = ContextSettings.from_file().assert_context()
    config = Config.from_remote(context)
    pulumi_config = DSHPulumiConfig.from_remote(context)
    pulumi_project = pulumi_config[name]

    sre_name = sanitise_sre_name(name)
    try:
        # Load GraphAPI as this may require user-interaction that is not possible as
        # part of a Pulumi declarative command
        graph_api = GraphApi(
            tenant_id=config.shm.entra_id_tenant_id,
            default_scopes=["Application.ReadWrite.All", "Group.ReadWrite.All"],
        )

        # Remove infrastructure deployed with Pulumi
        try:
            stack = SREProjectManager(
                context,
                config,
                pulumi_project,
                sre_name,
                graph_api_token=graph_api.token,
            )
            stack.teardown()
        except Exception as exc:
            msg = f"Unable to teardown Pulumi infrastructure.\n{exc}"
            raise DataSafeHavenInputError(msg) from exc

        # Remove Pulumi project from Pulumi config file
        del pulumi_config[name]

        # Upload Pulumi config to blob storage
        pulumi_config.upload(context)
    except DataSafeHavenError as exc:
        msg = f"Could not teardown Secure Research Environment '{sre_name}'.\n{exc}"
        raise DataSafeHavenError(msg) from exc
