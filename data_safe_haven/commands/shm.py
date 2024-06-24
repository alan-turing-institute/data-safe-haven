"""Command-line application for managing SHM infrastructure."""

from typing import Annotated, Optional

import typer

from data_safe_haven.config import DSHPulumiConfig, SHMConfig
from data_safe_haven.context import ContextSettings
from data_safe_haven.exceptions import DataSafeHavenError, DataSafeHavenPulumiError
from data_safe_haven.external import GraphApi
from data_safe_haven.infrastructure import SHMProjectManager

shm_command_group = typer.Typer()


@shm_command_group.command()
def deploy(
    force: Annotated[
        Optional[bool],  # noqa: UP007
        typer.Option(
            "--force",
            "-f",
            help="Force this operation, cancelling any others that are in progress.",
        ),
    ] = None,
) -> None:
    """Deploy a Safe Haven Management environment."""
    context = ContextSettings.from_file().assert_context()
    config = SHMConfig.from_remote(context)
    pulumi_config = DSHPulumiConfig.from_remote_or_create(
        context, encrypted_key=None, projects={}
    )

    try:
        # Connect to GraphAPI interactively
        graph_api = GraphApi(
            tenant_id=config.shm.entra_tenant_id,
            default_scopes=[
                "Application.ReadWrite.All",
                "Domain.ReadWrite.All",
                "Group.ReadWrite.All",
            ],
        )
        verification_record = graph_api.add_custom_domain(config.shm.fqdn)

        # Initialise Pulumi stack
        stack = SHMProjectManager(
            context=context,
            config=config,
            pulumi_config=pulumi_config,
            create_project=True,
        )
        # Set Azure options
        stack.add_option("azure-native:location", context.location, replace=False)
        stack.add_option(
            "azure-native:subscriptionId",
            config.azure.subscription_id,
            replace=False,
        )
        stack.add_option("azure-native:tenantId", config.azure.tenant_id, replace=False)
        # Add necessary secrets
        stack.add_secret(
            "verification-azuread-custom-domain", verification_record, replace=False
        )

        # Deploy Azure infrastructure with Pulumi
        if force is None:
            stack.deploy()
        else:
            stack.deploy(force=force)

        # Add the SHM domain to Entra ID as a custom domain
        graph_api.verify_custom_domain(
            stack.output("networking")["fqdn"],
            stack.output("networking")["fqdn_nameservers"],
        )
    except DataSafeHavenError as exc:
        # Note, would like to exit with a non-zero code here.
        # However, typer.Exit does not print the exception tree which is very unhelpful
        # for figuring out what went wrong.
        # print("Could not deploy Data Safe Haven Management environment.")
        # raise typer.Exit(code=1) from exc
        msg = f"Could not deploy Data Safe Haven Management environment.\n{exc}"
        raise DataSafeHavenError(msg) from exc
    finally:
        # Upload Pulumi config to blob storage
        pulumi_config.upload(context)


@shm_command_group.command()
def teardown() -> None:
    """Tear down a deployed a Safe Haven Management environment."""
    context = ContextSettings.from_file().assert_context()
    config = SHMConfig.from_remote(context)
    pulumi_config = DSHPulumiConfig.from_remote(context)

    try:
        # Remove infrastructure deployed with Pulumi
        try:
            stack = SHMProjectManager(
                context=context,
                config=config,
                pulumi_config=pulumi_config,
            )
            stack.teardown()
        except Exception as exc:
            msg = f"Unable to teardown Pulumi infrastructure.\n{exc}"
            raise DataSafeHavenPulumiError(msg) from exc

        # Remove information from config file
        del pulumi_config[context.shm_name]

        # Upload Pulumi config to blob storage
        pulumi_config.upload(context)
    except DataSafeHavenError as exc:
        msg = f"Could not teardown Safe Haven Management environment.\n{exc}"
        raise DataSafeHavenError(msg) from exc
