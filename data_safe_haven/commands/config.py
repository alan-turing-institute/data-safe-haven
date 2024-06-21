"""Command group and entrypoints for managing DSH configuration"""

from pathlib import Path
from typing import Annotated, Optional

import typer

from data_safe_haven import console
from data_safe_haven.config import ContextSettings, SHMConfig, SREConfig
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
    context = ContextSettings.from_file().assert_context()
    config = SHMConfig.from_remote(context)
    config_yaml = config.to_yaml()
    if file:
        with open(file, "w") as outfile:
            outfile.write(config_yaml)
    else:
        console.print(config_yaml)


@config_command_group.command()
def template_shm(
    file: Annotated[
        Optional[Path],  # noqa: UP007
        typer.Option(help="File path to write configuration template to."),
    ] = None
) -> None:
    """Write a template Data Safe Haven SHM configuration."""
    shm_config = SHMConfig.template()
    # The template uses explanatory strings in place of the expected types.
    # Serialisation warnings are therefore suppressed to avoid misleading the users into
    # thinking there is a problem and contaminating the output.
    config_yaml = shm_config.to_yaml(warnings=False)
    if file:
        with open(file, "w") as outfile:
            outfile.write(config_yaml)
    else:
        console.print(config_yaml)


@config_command_group.command()
def upload_shm(
    file: Annotated[Path, typer.Argument(help="Path to configuration file")],
) -> None:
    """Upload an SHM configuration to the Data Safe Haven context"""
    context = ContextSettings.from_file().assert_context()

    # Create configuration object from file
    with open(file) as config_file:
        config_yaml = config_file.read()
    config = SHMConfig.from_yaml(config_yaml)

    # Present diff to user
    if SHMConfig.remote_exists(context):
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
                raise typer.Exit()
        else:
            console.print("No changes, won't upload configuration.")
            raise typer.Exit()

    config.upload(context)


# Commands related to an SRE
@config_command_group.command()
def show_sre(
    name: Annotated[str, typer.Argument(help="Name of SRE to show")],
    file: Annotated[
        Optional[Path],  # noqa: UP007
        typer.Option(help="File path to write configuration template to."),
    ] = None,
) -> None:
    """Print the SRE configuration for the selected SRE and Data Safe Haven context"""
    context = ContextSettings.from_file().assert_context()
    sre_config = SREConfig.from_remote_by_name(context, name)
    config_yaml = sre_config.to_yaml()
    if file:
        with open(file, "w") as outfile:
            outfile.write(config_yaml)
    else:
        console.print(config_yaml)


@config_command_group.command()
def template_sre(
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
def upload_sre(
    file: Annotated[Path, typer.Argument(help="Path to configuration file")],
) -> None:
    """Upload an SRE configuration to the Data Safe Haven context"""
    context = ContextSettings.from_file().assert_context()
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

    config.upload(context, filename=config.filename)
