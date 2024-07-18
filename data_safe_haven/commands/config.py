"""Command group and entrypoints for managing DSH configuration"""

from pathlib import Path
from typing import Annotated, Optional

import typer

from data_safe_haven import console
from data_safe_haven.config import ContextManager, SHMConfig, SREConfig
from data_safe_haven.exceptions import (
    DataSafeHavenAzureStorageError,
    DataSafeHavenError,
)
from data_safe_haven.logging import get_logger

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
    context = ContextManager.from_file().assert_context()
    logger = get_logger()
    try:
        config = SHMConfig.from_remote(context)
    except DataSafeHavenError as exc:
        logger.critical("No SHM configuration exists for the selected context.")
        raise typer.Exit(1) from exc
    config_yaml = config.to_yaml()
    if file:
        with open(file, "w") as outfile:
            outfile.write(config_yaml)
    else:
        console.print(config_yaml)


# Commands related to an SRE
@config_command_group.command()
def show(
    name: Annotated[str, typer.Argument(help="Name of SRE to show")],
    file: Annotated[
        Optional[Path],  # noqa: UP007
        typer.Option(help="File path to write configuration template to."),
    ] = None,
) -> None:
    """Print the SRE configuration for the selected SRE and Data Safe Haven context"""
    context = ContextManager.from_file().assert_context()
    logger = get_logger()
    try:
        sre_config = SREConfig.from_remote_by_name(context, name)
    except DataSafeHavenAzureStorageError as exc:
        logger.critical(
            "Failed to interact with Azure storage for the selected context. \n"
            "Ensure SHM is deployed before attempting to use SRE configs."
        )
        raise typer.Exit(1) from exc
    except DataSafeHavenError as exc:
        logger.critical(
            f"No configuration exists for an SRE named '{name}' for the selected context."
        )
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
    ] = None
) -> None:
    """Write a template Data Safe Haven SRE configuration."""
    sre_config = SREConfig.template()
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
    file: Annotated[Path, typer.Argument(help="Path to configuration file")],
) -> None:
    """Upload an SRE configuration to the Data Safe Haven context"""
    context = ContextManager.from_file().assert_context()
    logger = get_logger()

    # Create configuration object from file
    with open(file) as config_file:
        config_yaml = config_file.read()
    config = SREConfig.from_yaml(config_yaml)

    # Present diff to user
    if SREConfig.remote_exists(context, filename=config.filename):
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

    try:
        config.upload(context, filename=config.filename)
    except DataSafeHavenError as exc:
        logger.critical("No infrastructure found for the selected context.")
        raise typer.Exit(1) from exc
