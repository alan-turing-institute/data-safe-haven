"""Command-line application for managing SHM infrastructure."""

from typing import Annotated, Optional

import typer

from data_safe_haven import console
from data_safe_haven.config import ContextManager, SHMConfig
from data_safe_haven.exceptions import (
    DataSafeHavenAzureAPIAuthenticationError,
    DataSafeHavenConfigError,
    DataSafeHavenError,
)
from data_safe_haven.infrastructure import ImperativeSHM
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
    fqdn: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="Domain name you want your TRE to be accessible at.",
            callback=typer_fqdn,
        ),
    ] = None,
    location: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="The Azure location to deploy resources into.",
        ),
    ] = None,
) -> None:
    """Deploy a Safe Haven Management environment using the current context."""
    logger = get_logger()

    # Load selected context
    try:
        context = ContextManager.from_file().assert_context()
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
    try:
        if SHMConfig.remote_exists(context):
            config = SHMConfig.from_remote(context)
            # If command line arguments conflict with the remote version then present diff
            if fqdn:
                config.shm.fqdn = fqdn
            if entra_tenant_id:
                config.shm.entra_tenant_id = entra_tenant_id
            if location:
                config.azure.location = location
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
            if not entra_tenant_id:
                logger.critical(
                    "You must provide the --entra-tenant-id argument when first deploying an SHM."
                )
                raise typer.Exit(1)
            if not fqdn:
                logger.critical(
                    "You must provide the --fqdn argument when first deploying an SHM."
                )
                raise typer.Exit(1)
            if not location:
                logger.critical(
                    "You must provide the --location argument when first deploying an SHM."
                )
                raise typer.Exit(1)
            config = SHMConfig.from_args(
                context,
                entra_tenant_id=entra_tenant_id,
                fqdn=fqdn,
                location=location,
            )
    except DataSafeHavenError as exc:
        msg = "Failed to load SHM configuration."
        logger.critical(msg)
        raise typer.Exit(1) from exc

    # Create Data Safe Haven SHM infrastructure.
    try:
        shm_infra = ImperativeSHM(context, config)
        shm_infra.deploy()
    except DataSafeHavenAzureAPIAuthenticationError as exc:
        msg = "Failed to authenticate with the Azure API. You may not be logged into the Azure CLI, or your login may have expired. Try running `az login`."
        logger.critical(msg)
        raise typer.Exit(1) from exc
    except DataSafeHavenError as exc:
        msg = "Failed to deploy Data Safe Haven infrastructure."
        logger.critical(msg)
        raise typer.Exit(1) from exc
    # Upload config file to blob storage
    config.upload(context)


@shm_command_group.command()
def teardown() -> None:
    """Tear down a deployed Safe Haven Management environment."""
    logger = get_logger()
    try:
        context = ContextManager.from_file().assert_context()
    except DataSafeHavenConfigError as exc:
        if exc.args[0] == "No context selected":
            msg = "No context selected. Use `dsh context switch` to select one."
        else:
            msg = "No context configuration file. Use `dsh context add` before creating infrastructure."
        logger.critical(msg)
        raise typer.Exit(code=1) from exc

    # Teardown Data Safe Haven SHM infrastructure.
    try:
        if SHMConfig.remote_exists(context):
            config = SHMConfig.from_remote(context)
            shm_infra = ImperativeSHM(context, config)
            console.print(
                "Tearing down the Safe Haven Management environment will permanently delete all associated resources, including remotely stored configurations."
            )
            if not console.confirm(
                "Do you wish to continue tearing down the SHM?", default_to_yes=False
            ):
                console.print("SHM teardown cancelled by user.")
                raise typer.Exit(0)
            shm_infra.teardown()
        else:
            logger.critical(f"No deployed SHM found for context [green]{context.name}.")
            raise typer.Exit(1)
    except DataSafeHavenError as exc:
        logger.critical("Could not teardown Safe Haven Management environment.")
        raise typer.Exit(1) from exc
