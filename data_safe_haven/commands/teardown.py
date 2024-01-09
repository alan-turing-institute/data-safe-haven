"""Command-line application for tearing down a Data Safe Haven component, delegating the details to a subcommand"""
from typing import Annotated

import typer

from data_safe_haven.config import Config, ContextSettings
from data_safe_haven.exceptions import (
    DataSafeHavenError,
    DataSafeHavenInputError,
)
from data_safe_haven.external import GraphApi
from data_safe_haven.infrastructure import SHMStackManager, SREStackManager

teardown_command_group = typer.Typer()


@teardown_command_group.command(
    help="Tear down a deployed a Safe Haven Management component."
)
def shm() -> None:
    context = ContextSettings.from_file().assert_context()
    config = Config.from_remote(context)

    try:
        # Remove infrastructure deployed with Pulumi
        try:
            stack = SHMStackManager(config)
            stack.teardown()
        except Exception as exc:
            msg = f"Unable to teardown Pulumi infrastructure.\n{exc}"
            raise DataSafeHavenInputError(msg) from exc

        # Remove information from config file
        if stack.stack_name in config.pulumi.stacks.keys():
            del config.pulumi.stacks[stack.stack_name]

        # Upload config to blob storage
        config.upload()
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

    sre_name = config.sanitise_sre_name(name)
    try:
        # Load GraphAPI as this may require user-interaction that is not possible as
        # part of a Pulumi declarative command
        graph_api = GraphApi(
            tenant_id=config.shm.aad_tenant_id,
            default_scopes=["Application.ReadWrite.All", "Group.ReadWrite.All"],
        )

        # Remove infrastructure deployed with Pulumi
        try:
            stack = SREStackManager(config, sre_name, graph_api_token=graph_api.token)
            if stack.work_dir.exists():
                stack.teardown()
            else:
                msg = f"SRE {sre_name} not found - check the name is spelt correctly."
                raise DataSafeHavenInputError(msg)
        except Exception as exc:
            msg = f"Unable to teardown Pulumi infrastructure.\n{exc}"
            raise DataSafeHavenInputError(msg) from exc

        # Remove information from config file
        config.remove_stack(stack.stack_name)
        config.remove_sre(sre_name)

        # Upload config to blob storage
        config.upload()
    except DataSafeHavenError as exc:
        msg = f"Could not teardown Secure Research Environment '{sre_name}'.\n{exc}"
        raise DataSafeHavenError(msg) from exc
