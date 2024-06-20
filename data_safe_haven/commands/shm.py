"""Command-line application for managing SHM infrastructure."""

from typing import Annotated, Optional

import typer

from data_safe_haven.config import DSHPulumiConfig, SHMConfig
from data_safe_haven.context import ContextSettings
from data_safe_haven.context_infrastructure import ContextInfrastructure
from data_safe_haven.exceptions import (
    DataSafeHavenAzureAPIAuthenticationError,
    DataSafeHavenConfigError,
    DataSafeHavenError,
    DataSafeHavenInputError,
)
from data_safe_haven.external import GraphApi
from data_safe_haven.infrastructure import SHMProjectManager
from data_safe_haven.logging import get_logger

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
    # Create Data Safe Haven context infrastructure.
    logger = get_logger()
    try:
        context = ContextSettings.from_file().assert_context()
    except DataSafeHavenConfigError as exc:
        if exc.args[0] == "No context selected":
            logger.critical(
                "No context selected. Use `dsh context switch` to select one."
            )
        else:
            logger.critical(
                "No context configuration file. Use `dsh context add` before creating infrastructure."
            )
        raise typer.Exit(1) from exc

    context_infra = ContextInfrastructure(context)
    try:
        context_infra.create()
    except DataSafeHavenAzureAPIAuthenticationError as exc:
        logger.critical(
            "Failed to authenticate with the Azure API. You may not be logged into the Azure CLI, or your login may have expired. Try running `az login`."
        )
        raise typer.Exit(1) from exc

    # Deploy the Data Safe Haven SHM infrastructure
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
        msg = "Could not deploy Data Safe Haven Management environment."
        raise DataSafeHavenError(msg) from exc
    finally:
        # Upload Pulumi config to blob storage
        pulumi_config.upload(context)


@shm_command_group.command()
def teardown() -> None:
    """Tear down a deployed a Safe Haven Management environment."""
    # Teardown Data Safe Haven context infrastructure.
    logger = get_logger()
    try:
        context = ContextSettings.from_file().assert_context()
    except DataSafeHavenConfigError as exc:
        if exc.args[0] == "No context selected":
            logger.critical(
                "No context selected. Use `dsh context switch` to select one."
            )
        else:
            logger.critical(
                "No context configuration file. Use `dsh context add` before creating infrastructure."
            )
        raise typer.Exit(code=1) from exc

    try:
        context_infra = ContextInfrastructure(context)
        context_infra.teardown()
    except DataSafeHavenAzureAPIAuthenticationError as exc:
        logger.critical(
            "Failed to authenticate with the Azure API. You may not be logged into the Azure CLI, or your login may have expired. Try running `az login`."
        )
        raise typer.Exit(1) from exc

    # Teardown Data Safe Haven SHM infrastructure deployed with Pulumi
    config = SHMConfig.from_remote(context)
    pulumi_config = DSHPulumiConfig.from_remote(context)
    try:
        try:
            # Teardown the Pulumi project
            stack = SHMProjectManager(
                context=context,
                config=config,
                pulumi_config=pulumi_config,
            )
            stack.teardown()

            # Remove information from config file
            del pulumi_config[context.shm_name]

            # Upload Pulumi config to blob storage
            pulumi_config.upload(context)
        except Exception as exc:
            msg = "Unable to teardown Pulumi infrastructure."
            raise DataSafeHavenInputError(msg) from exc

    except DataSafeHavenError as exc:
        msg = "Could not teardown Safe Haven Management environment."
        raise DataSafeHavenError(msg) from exc
