"""Command-line application for managing SRE infrastructure."""

from typing import Annotated

import typer

from data_safe_haven.config import ContextManager, DSHPulumiConfig, SHMConfig, SREConfig
from data_safe_haven.exceptions import DataSafeHavenConfigError, DataSafeHavenError
from data_safe_haven.external import AzureSdk, GraphApi
from data_safe_haven.functions import current_ip_address, ip_address_in_list
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.logging import get_logger
from data_safe_haven.provisioning import SREProvisioningManager

sre_command_group = typer.Typer()


@sre_command_group.command()
def deploy(
    name: Annotated[str, typer.Argument(help="Name of SRE to deploy")],
    force: Annotated[  # noqa: FBT002
        bool,
        typer.Option(
            "--force",
            "-f",
            help="Force this operation, cancelling any others that are in progress.",
        ),
    ] = False,
) -> None:
    """Deploy a Secure Research Environment"""
    logger = get_logger()
    try:
        # Load context and SHM config
        context = ContextManager.from_file().assert_context()
        shm_config = SHMConfig.from_remote(context)

        # Load GraphAPI
        graph_api = GraphApi.from_scopes(
            scopes=[
                "Application.ReadWrite.All",
                "AppRoleAssignment.ReadWrite.All",
                "Directory.ReadWrite.All",
                "Group.ReadWrite.All",
            ],
            tenant_id=shm_config.shm.entra_tenant_id,
        )

        # Load Pulumi and SRE configs
        pulumi_config = DSHPulumiConfig.from_remote_or_create(
            context, encrypted_key=None, projects={}
        )
        sre_config = SREConfig.from_remote_by_name(context, name)

        # Check whether current IP address is authorised to take administrator actions
        if not ip_address_in_list(sre_config.sre.admin_ip_addresses):
            logger.warning(
                f"IP address '{current_ip_address()}' is not authorised to deploy SRE '{sre_config.description}'."
            )
            msg = "Check that 'admin_ip_addresses' is set correctly in your SRE config file."
            raise DataSafeHavenConfigError(msg)

        # Initialise Pulumi stack
        # Note that requesting a GraphApi token will trigger possible user-interaction
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
        # Get SRE subscription name
        azure_sdk = AzureSdk(subscription_name=context.subscription_name)
        sre_subscription_name = azure_sdk.get_subscription_name(
            sre_config.azure.subscription_id
        )
        stack.add_option(
            "sre-subscription-name",
            sre_subscription_name,
            replace=True,
        )
        logger.info(
            f"SRE will be deployed to subscription '[green]{sre_subscription_name}[/]'"
            f" ('[bold]{sre_config.azure.subscription_id}[/]')"
        )
        # Set Entra options
        application = graph_api.get_application_by_name(context.entra_application_name)
        if not application:
            msg = f"No Entra application '{context.entra_application_name}' was found. Please redeploy your SHM."
            raise DataSafeHavenConfigError(msg)
        stack.add_option("azuread:clientId", application.get("appId", ""), replace=True)
        if not context.entra_application_secret:
            msg = f"No Entra application secret '{context.entra_application_secret_name}' was found. Please redeploy your SHM."
            raise DataSafeHavenConfigError(msg)
        stack.add_secret(
            "azuread:clientSecret", context.entra_application_secret, replace=True
        )
        stack.add_option(
            "azuread:tenantId", shm_config.shm.entra_tenant_id, replace=True
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
        stack.add_option(
            "shm-location",
            shm_config.azure.location,
            replace=True,
        )
        stack.add_option(
            "shm-subscription-id",
            shm_config.azure.subscription_id,
            replace=True,
        )
        logger.info(f"SRE will be registered in SHM '[green]{shm_config.shm.fqdn}[/]'")
        logger.info(f"SHM subscription '[green]{shm_config.azure.subscription_id}[/]'")

        # Deploy Azure infrastructure with Pulumi
        try:
            stack.deploy(force=force)
        finally:
            # Upload Pulumi config to blob storage
            pulumi_config.upload(context)

        # Provision SRE with anything that could not be done in Pulumi
        manager = SREProvisioningManager(
            graph_api_token=graph_api.token,
            location=sre_config.azure.location,
            sre_name=sre_config.name,
            sre_stack=stack,
            subscription_name=sre_subscription_name,
            timezone=sre_config.sre.timezone,
        )
        manager.run()
    except DataSafeHavenError as exc:
        logger.critical(
            f"Could not deploy Secure Research Environment '[green]{name}[/]'."
        )
        raise typer.Exit(code=1) from exc


@sre_command_group.command()
def teardown(
    name: Annotated[str, typer.Argument(help="Name of SRE to teardown.")],
    force: Annotated[  # noqa: FBT002
        bool,
        typer.Option(
            "--force",
            "-f",
            help="Force this operation, cancelling any others that are in progress.",
        ),
    ] = False,
) -> None:
    """Tear down a deployed a Secure Research Environment."""
    logger = get_logger()
    try:
        # Load context and SHM config
        context = ContextManager.from_file().assert_context()
        shm_config = SHMConfig.from_remote(context)

        # Load GraphAPI as this may require user-interaction
        graph_api = GraphApi.from_scopes(
            scopes=["Application.ReadWrite.All", "Group.ReadWrite.All"],
            tenant_id=shm_config.shm.entra_tenant_id,
        )

        # Load Pulumi and SRE configs
        pulumi_config = DSHPulumiConfig.from_remote(context)
        sre_config = SREConfig.from_remote_by_name(context, name)

        # Check whether current IP address is authorised to take administrator actions
        if not ip_address_in_list(sre_config.sre.admin_ip_addresses):
            logger.warning(
                f"IP address '{current_ip_address()}' is not authorised to teardown SRE '{sre_config.description}'."
            )
            msg = "Check that 'admin_ip_addresses' is set correctly in your SRE config file."
            raise DataSafeHavenConfigError(msg)

        # Remove infrastructure deployed with Pulumi
        # N.B. We allow the creation of a project (which is immediately removed)
        # to stop Pulumi operations from crashing due to a missing stack
        stack = SREProjectManager(
            context=context,
            config=sre_config,
            pulumi_config=pulumi_config,
            graph_api_token=graph_api.token,
            create_project=True,
        )
        stack.teardown(force=force)

        # Remove Pulumi project from Pulumi config file
        del pulumi_config[name]

        # Upload Pulumi config to blob storage
        pulumi_config.upload(context)
    except DataSafeHavenError as exc:
        logger.critical(
            f"Could not teardown Secure Research Environment '[green]{name}[/]'."
        )
        raise typer.Exit(1) from exc
