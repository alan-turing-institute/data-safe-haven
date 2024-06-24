"""Command-line application for managing SHM infrastructure."""

from typing import Annotated, Optional

import typer

from data_safe_haven import console
from data_safe_haven.config import ContextSettings, DSHPulumiConfig, SHMConfig
from data_safe_haven.exceptions import (
    DataSafeHavenAzureAPIAuthenticationError,
    DataSafeHavenConfigError,
    DataSafeHavenError,
    DataSafeHavenInputError,
    DataSafeHavenMicrosoftGraphError,
)
from data_safe_haven.external import GraphApi
from data_safe_haven.infrastructure import BackendInfrastructure, SHMProjectManager
from data_safe_haven.logging import get_logger
from data_safe_haven.validators import typer_aad_guid, typer_fqdn

shm_command_group = typer.Typer()


@shm_command_group.command()
def deploy(
    entra_tenant_id: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="Tenant ID for the Entra ID used to manage TRE users.",
            callback=typer_aad_guid,
        ),
    ] = None,
    force: Annotated[
        Optional[bool],  # noqa: UP007
        typer.Option(
            "--force",
            "-f",
            help="Force this operation, cancelling any others that are in progress.",
        ),
    ] = None,
    fqdn: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="Domain name you want your TRE to be accessible at.",
            callback=typer_fqdn,
        ),
    ] = None,
) -> None:
    """Deploy a Safe Haven Management environment."""
    # Load selected context
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

    # Load SHM config from remote if it exists or locally if not
    if SHMConfig.remote_exists(context):
        config = SHMConfig.from_remote(context)
        # If command line arguments conflict with the remote version then present diff
        if fqdn:
            config.shm.fqdn = fqdn
        if entra_tenant_id:
            config.shm.entra_tenant_id = entra_tenant_id
        if diff := config.remote_yaml_diff(context):
            logger = get_logger()
            for line in "".join(diff).splitlines():
                logger.info(line)
            if not console.confirm(
                (
                    "Configuration has changed, "
                    "do you want to overwrite the remote configuration?"
                ),
                default_to_yes=False,
            ):
                raise typer.Exit(0)
    else:
        if not fqdn:
            logger.critical(
                "You must provide the --fqdn argument when first deploying an SHM."
            )
            raise typer.Exit(1)
        if not entra_tenant_id:
            logger.critical(
                "You must provide the --entra-tenant-id argument when first deploying an SHM."
            )
            raise typer.Exit(1)
        config = SHMConfig.from_local(
            context, entra_tenant_id=entra_tenant_id, fqdn=fqdn
        )
    # Upload config file to blob storage
    config.upload(context)

    # Add the SHM domain to the Entra ID via interactive GraphAPI
    try:
        graph_api = GraphApi(
            tenant_id=config.shm.entra_tenant_id,
            default_scopes=[
                "Application.ReadWrite.All",
                "Domain.ReadWrite.All",
                "Group.ReadWrite.All",
            ],
        )
        verification_record = graph_api.add_custom_domain(config.shm.fqdn)
    except DataSafeHavenMicrosoftGraphError as exc:
        msg = f"Failed to add custom domain '{config.shm.fqdn}' to Entra ID."
        logger.critical(msg)
        raise typer.Exit(1) from exc

    # Create Data Safe Haven context infrastructure.
    try:
        context_infra = BackendInfrastructure(context, config)
        context_infra.create()
    except DataSafeHavenAzureAPIAuthenticationError as exc:
        msg = "Failed to authenticate with the Azure API. You may not be logged into the Azure CLI, or your login may have expired. Try running `az login`."
        logger.critical(msg)
        raise typer.Exit(1) from exc

    # Create/load the Pulumi config and upload it to blob storage
    pulumi_config = DSHPulumiConfig.from_remote_or_create(
        context, encrypted_key=None, projects={}
    )
    pulumi_config.upload(context)

    # Deploy the Data Safe Haven SHM infrastructure
    try:
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
            config.shm.fqdn,
            context_infra.nameservers,
        )
    except DataSafeHavenError as exc:
        # Note, would like to exit with a non-zero code here.
        # However, typer.Exit does not print the exception tree which is very unhelpful
        # for figuring out what went wrong.
        # print("Could not deploy Data Safe Haven Management environment.")
        # raise typer.Exit(code=1) from exc
        msg = "Could not deploy Data Safe Haven Management environment."
        raise DataSafeHavenError(msg) from exc


@shm_command_group.command()
def teardown() -> None:
    """Tear down a deployed a Safe Haven Management environment."""
    # Teardown Data Safe Haven context infrastructure.
    logger = get_logger()
    try:
        context = ContextSettings.from_file().assert_context()
    except DataSafeHavenConfigError as exc:
        if exc.args[0] == "No context selected":
            msg = "No context selected. Use `dsh context switch` to select one."
        else:
            msg = "No context configuration file. Use `dsh context add` before creating infrastructure."
        logger.critical(msg)
        raise typer.Exit(code=1) from exc

    try:
        config = SHMConfig.from_remote(context)
        context_infra = BackendInfrastructure(context, config)
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
