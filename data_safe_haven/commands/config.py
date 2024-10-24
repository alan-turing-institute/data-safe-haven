"""Command group and entrypoints for managing DSH configuration"""

from logging import Logger
from pathlib import Path
from typing import Annotated, Optional

import typer

from data_safe_haven import console
from data_safe_haven.config import (
    ContextManager,
    DSHPulumiConfig,
    SHMConfig,
    SREConfig,
    sre_config_name,
)
from data_safe_haven.exceptions import (
    DataSafeHavenAzureError,
    DataSafeHavenAzureStorageError,
    DataSafeHavenConfigError,
    DataSafeHavenError,
    DataSafeHavenTypeError,
)
from data_safe_haven.external.api.azure_sdk import AzureSdk
from data_safe_haven.logging import get_logger
from data_safe_haven.serialisers import ContextBase

config_command_group = typer.Typer()


# Commands related to an SHM
@config_command_group.command()
def show_shm(
    file: Annotated[
        Optional[Path],  # noqa: UP007
        typer.Option(help="File path to write configuration template to."),
    ] = None
) -> None:
    """Print the SHM configuration for the selected Data Safe Haven context"""
    logger = get_logger()
    try:
        context = ContextManager.from_file().assert_context()
    except DataSafeHavenConfigError as exc:
        logger.critical(
            "No context is selected. Use `dsh context add` to create a context "
            "or `dsh context switch` to select one."
        )
        raise typer.Exit(1) from exc

    try:
        config = SHMConfig.from_remote(context)
    except DataSafeHavenError as exc:
        logger.critical(
            "SHM must be deployed before its configuration can be displayed."
        )
        raise typer.Exit(1) from exc

    config_yaml = config.to_yaml()

    if file:
        with open(file, "w") as outfile:
            outfile.write(config_yaml)
    else:
        console.print(config_yaml)


# Commands related to an SRE
@config_command_group.command()
def available() -> None:
    """List the available SRE configurations for the selected Data Safe Haven context"""
    logger = get_logger()
    try:
        context = ContextManager.from_file().assert_context()
    except DataSafeHavenConfigError as exc:
        logger.critical(
            "No context is selected. Use `dsh context add` to create a context "
            "or `dsh context switch` to select one."
        )
        raise typer.Exit(1) from exc

    azure_sdk = AzureSdk(context.subscription_name)

    try:
        blobs = azure_sdk.list_blobs(
            container_name=context.storage_container_name,
            prefix="sre",
            resource_group_name=context.resource_group_name,
            storage_account_name=context.storage_account_name,
        )
    except DataSafeHavenAzureStorageError as exc:
        logger.critical("Ensure SHM is deployed before attempting to use SRE configs.")
        raise typer.Exit(1) from exc

    if not blobs:
        logger.info(f"No configurations found for context '{context.name}'.")
        raise typer.Exit(0)

    config_names = [blob.removeprefix("sre-").removesuffix(".yaml") for blob in blobs]
    pulumi_config = DSHPulumiConfig.from_remote(context)
    deployed = pulumi_config.project_names

    headers = ["SRE Name", "Deployed"]
    rows = [[name, "x" if name in deployed else ""] for name in config_names]
    console.print(f"Available SRE configurations for context '{context.name}':")
    console.tabulate(headers, rows)


@config_command_group.command()
def show(
    name: Annotated[str, typer.Argument(help="Name of SRE to show")],
    file: Annotated[
        Optional[Path],  # noqa: UP007
        typer.Option(help="File path to write configuration template to."),
    ] = None,
) -> None:
    """Print the SRE configuration for the selected SRE and Data Safe Haven context"""
    logger = get_logger()

    try:
        context = ContextManager.from_file().assert_context()
    except DataSafeHavenConfigError as exc:
        logger.critical(
            "No context is selected. Use `dsh context add` to create a context "
            "or `dsh context switch` to select one."
        )
        raise typer.Exit(1) from exc

    try:
        sre_config = SREConfig.from_remote_by_name(context, name)
    except DataSafeHavenAzureStorageError as exc:
        logger.critical("Ensure SHM is deployed before attempting to use SRE configs.")
        raise typer.Exit(1) from exc
    except DataSafeHavenAzureError as exc:
        logger.critical(
            f"No configuration exists for an SRE named '{name}' for the selected context."
        )
        raise typer.Exit(1) from exc
    except DataSafeHavenTypeError as exc:
        dump_remote_config(context, name, logger)
        raise typer.Exit(1) from exc

    config_yaml = sre_config.to_yaml()

    if file:
        with open(file, "w") as outfile:
            outfile.write(config_yaml)
    else:
        console.print(config_yaml)


@config_command_group.command()
def template(
    file: Annotated[
        Optional[Path],  # noqa: UP007
        typer.Option(help="File path to write configuration template to."),
    ] = None,
    tier: Annotated[
        Optional[int],  # noqa: UP007
        typer.Option(help="Which security tier to base this template on."),
    ] = None,
) -> None:
    """Write a template Data Safe Haven SRE configuration."""
    sre_config = SREConfig.template(tier)
    # The template uses explanatory strings in place of the expected types.
    # Serialisation warnings are therefore suppressed to avoid misleading the users into
    # thinking there is a problem and contaminating the output.
    config_yaml = sre_config.to_yaml(warnings=False)

    if file:
        with open(file, "w") as outfile:
            outfile.write(config_yaml)
    else:
        console.print(config_yaml)


@config_command_group.command()
def upload(
    file: Annotated[Path, typer.Argument(help="Path to configuration file.")],
    force: Annotated[  # noqa: FBT002
        bool,
        typer.Option(
            help="Skip validation and difference calculation of remote configuration."
        ),
    ] = False,
) -> None:
    """Upload an SRE configuration to the Data Safe Haven context"""
    context = ContextManager.from_file().assert_context()
    logger = get_logger()

    # Create configuration object from file
    if file.is_file():
        with open(file) as config_file:
            config_yaml = config_file.read()
    else:
        logger.critical(f"Configuration file '{file}' not found.")
        raise typer.Exit(1)
    try:
        config = SREConfig.from_yaml(config_yaml)
    except DataSafeHavenTypeError as exc:
        logger.error("Check for missing or incorrect fields in the configuration.")
        raise typer.Exit(1) from exc

    # Present diff to user
    if (not force) and SREConfig.remote_exists(context, filename=config.filename):
        try:
            if diff := config.remote_yaml_diff(context, filename=config.filename):
                for line in "".join(diff).splitlines():
                    logger.info(line)
                if not console.confirm(
                    (
                        "Configuration has changed, "
                        "do you want to overwrite the remote configuration?"
                    ),
                    default_to_yes=False,
                ):
                    raise typer.Exit()
            else:
                console.print("No changes, won't upload configuration.")
                raise typer.Exit()
        except DataSafeHavenTypeError as exc:
            dump_remote_config(context, config.name, logger)
            console.print(
                "To overwrite the remote config, use `dsh config upload --force`"
            )
            raise typer.Exit(1) from exc

    try:
        config.upload(context, filename=config.filename)
    except DataSafeHavenError as exc:
        logger.critical("No infrastructure found for the selected context.")
        raise typer.Exit(1) from exc


def dump_remote_config(context: ContextBase, name: str, logger: Logger) -> None:
    logger.warning(
        f"Remote configuration for SRE '{name}' is not valid. Dumping remote file."
    )
    azure_sdk = AzureSdk(subscription_name=context.subscription_name)
    config_yaml = azure_sdk.download_blob(
        sre_config_name(name),
        context.resource_group_name,
        context.storage_account_name,
        context.storage_container_name,
    )
    console.print(config_yaml)
