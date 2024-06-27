"""Command-line application for managing SRE infrastructure."""

from typing import Annotated, Optional

import typer

from data_safe_haven.config import (
    ContextManager,
    DSHPulumiConfig,
    SHMConfig,
    SREConfig,
)
from data_safe_haven.exceptions import DataSafeHavenError, DataSafeHavenPulumiError
from data_safe_haven.external import GraphApi
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.logging import get_logger
from data_safe_haven.provisioning import SREProvisioningManager

sre_command_group = typer.Typer()


@sre_command_group.command()
def deploy(
    name: Annotated[str, typer.Argument(help="Name of SRE to deploy")],
    force: Annotated[
        Optional[bool],  # noqa: UP007
        typer.Option(
            "--force",
            "-f",
            help="Force this operation, cancelling any others that are in progress.",
        ),
    ] = None,
) -> None:
    """Deploy a Secure Research Environment"""
    context = ContextManager.from_file().assert_context()
    pulumi_config = DSHPulumiConfig.from_remote(context)
    shm_config = SHMConfig.from_remote(context)
    sre_config = SREConfig.from_remote_by_name(context, name)

    logger = get_logger()
    try:
        # Load GraphAPI as this may require user-interaction that is not possible as
        # part of a Pulumi declarative command
        graph_api = GraphApi(
            tenant_id=shm_config.shm.entra_tenant_id,
            default_scopes=[
                "Application.ReadWrite.All",
                "AppRoleAssignment.ReadWrite.All",
                "Directory.ReadWrite.All",
                "Group.ReadWrite.All",
            ],
        )

        # Initialise Pulumi stack
        stack = SREProjectManager(
            context=context,
            config=sre_config,
            pulumi_config=pulumi_config,
            create_project=True,
            graph_api_token=graph_api.token,
        )
        # Set Azure options
        stack.add_option(
            "azure-native:location", sre_config.azure.location, replace=False
        )
        stack.add_option(
            "azure-native:subscriptionId",
            sre_config.azure.subscription_id,
            replace=False,
        )
        stack.add_option(
            "azure-native:tenantId", sre_config.azure.tenant_id, replace=False
        )
        # Load SHM outputs
        stack.add_option(
            "shm-admin-group-id",
            shm_config.shm.admin_group_id,
            replace=True,
        )
        stack.add_option(
            "shm-entra-tenant-id",
            shm_config.shm.entra_tenant_id,
            replace=True,
        )
        stack.add_option(
            "shm-fqdn",
            shm_config.shm.fqdn,
            replace=True,
        )

        # Deploy Azure infrastructure with Pulumi
        if force is None:
            stack.deploy()
        else:
            stack.deploy(force=force)

        # Provision SRE with anything that could not be done in Pulumi
        manager = SREProvisioningManager(
            graph_api_token=graph_api.token,
            location=sre_config.azure.location,
            sre_name=sre_config.safe_name,
            sre_stack=stack,
            subscription_name=context.subscription_name,
            timezone=sre_config.sre.timezone,
        )
        manager.run()
    except DataSafeHavenError as exc:
        logger.critical(
            f"Could not deploy Secure Research Environment {sre_config.safe_name}."
        )
        raise typer.Exit(code=1) from exc
    finally:
        # Upload Pulumi config to blob storage
        pulumi_config.upload(context)


@sre_command_group.command()
def teardown(
    name: Annotated[str, typer.Argument(help="Name of SRE to teardown.")],
) -> None:
    """Tear down a deployed a Secure Research Environment."""
    context = ContextManager.from_file().assert_context()
    pulumi_config = DSHPulumiConfig.from_remote(context)
    shm_config = SHMConfig.from_remote(context)
    sre_config = SREConfig.from_remote_by_name(context, name)

    logger = get_logger()
    try:
        # Load GraphAPI as this may require user-interaction that is not possible as
        # part of a Pulumi declarative command
        graph_api = GraphApi(
            tenant_id=shm_config.shm.entra_tenant_id,
            default_scopes=["Application.ReadWrite.All", "Group.ReadWrite.All"],
        )

        # Remove infrastructure deployed with Pulumi
        try:
            stack = SREProjectManager(
                context=context,
                config=sre_config,
                pulumi_config=pulumi_config,
                graph_api_token=graph_api.token,
            )
            stack.teardown()
        except Exception as exc:
            msg = "Unable to teardown Pulumi infrastructure."
            raise DataSafeHavenPulumiError(msg) from exc

        # Remove Pulumi project from Pulumi config file
        del pulumi_config[name]

        # Upload Pulumi config to blob storage
        pulumi_config.upload(context)
    except DataSafeHavenError as exc:
        logger.critical(
            f"Could not teardown Secure Research Environment '{sre_config.safe_name}'."
        )
        raise typer.Exit(1) from exc
