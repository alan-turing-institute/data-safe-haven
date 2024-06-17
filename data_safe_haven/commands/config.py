"""Command group and entrypoints for managing DSH configuration"""

from pathlib import Path
from typing import Annotated, Optional

import typer
from rich import print

from data_safe_haven.config import Config, SHMConfig
from data_safe_haven.context import ContextSettings
from data_safe_haven.utility import LoggingSingleton

config_command_group = typer.Typer()


@config_command_group.command()
def template(
    file: Annotated[
        Optional[Path],  # noqa: UP007
        typer.Option(help="File path to write configuration template to."),
    ] = None
) -> None:
    """Write a template Data Safe Haven configuration."""
    config = Config.template()
    # The template uses explanatory strings in place of the expected types.
    # Serialisation warnings are therefore suppressed to avoid misleading the users into
    # thinking there is a problem and contaminating the output.
    config_yaml = config.to_yaml(warnings=False)
    if file:
        with open(file, "w") as outfile:
            outfile.write(config_yaml)
    else:
        print(config_yaml)


@config_command_group.command()
def template_sre(
    file: Annotated[
        Optional[Path],  # noqa: UP007
        typer.Option(help="File path to write configuration template to."),
    ] = None
) -> None:
    """Write a template Data Safe Haven SRE configuration."""
    config = Config.template()
    # The template uses explanatory strings in place of the expected types.
    # Serialisation warnings are therefore suppressed to avoid misleading the users into
    # thinking there is a problem and contaminating the output.
    config_yaml = config.to_yaml(warnings=False)
    if file:
        with open(file, "w") as outfile:
            outfile.write(config_yaml)
    else:
        print(config_yaml)


@config_command_group.command()
def upload(
    file: Annotated[Path, typer.Argument(help="Path to configuration file")],
) -> None:
    """Upload a configuration to the Data Safe Haven context"""
    context = ContextSettings.from_file().assert_context()
    logger = LoggingSingleton()

    # Create configuration object from file
    with open(file) as config_file:
        config_yaml = config_file.read()
    config = SHMConfig.from_yaml(config_yaml)

    # Present diff to user
    if SHMConfig.remote_exists(context):
        if diff := config.remote_yaml_diff(context):
            print("".join(diff))
            if not logger.confirm(
                (
                    "Configuration has changed, "
                    "do you want to overwrite the remote configuration?"
                ),
                default_to_yes=False,
            ):
                raise typer.Exit()
        else:
            print("No changes, won't upload configuration.")
            raise typer.Exit()

    config.upload(context)


@config_command_group.command()
def upload_sre(
    file: Annotated[Path, typer.Argument(help="Path to configuration file")],
    name: Annotated[str, typer.Argument(help="Name of SRE to upload")],
) -> None:
    """Upload an SRE configuration to the Data Safe Haven context"""
    context = ContextSettings.from_file().assert_context()
    logger = LoggingSingleton()

    # Create configuration object from file
    with open(file) as config_file:
        config_yaml = config_file.read()
    config = Config.from_yaml(config_yaml)
    filename = Config.sre_filename_from_name(name)

    # Present diff to user
    if Config.remote_exists(context, filename=filename):
        if diff := config.remote_yaml_diff(context, filename=filename):
            print("".join(diff))
            if not logger.confirm(
                (
                    "Configuration has changed, "
                    "do you want to overwrite the remote configuration?"
                ),
                default_to_yes=False,
            ):
                raise typer.Exit()
        else:
            print("No changes, won't upload configuration.")
            raise typer.Exit()

    config.upload(context, filename=filename)


@config_command_group.command()
def show(
    file: Annotated[
        Optional[Path],  # noqa: UP007
        typer.Option(help="File path to write configuration template to."),
    ] = None
) -> None:
    """Print the configuration for the selected Data Safe Haven context"""
    context = ContextSettings.from_file().assert_context()
    config = SHMConfig.from_remote(context)
    if file:
        with open(file, "w") as outfile:
            outfile.write(config.to_yaml())
    else:
        print(config.to_yaml())


@config_command_group.command()
def show_sre(
    name: Annotated[str, typer.Argument(help="Name of SRE to upload")],
    file: Annotated[
        Optional[Path],  # noqa: UP007
        typer.Option(help="File path to write configuration template to."),
    ] = None,
) -> None:
    """Print the configuration for the selected Data Safe Haven context"""
    context = ContextSettings.from_file().assert_context()
    config = Config.sre_from_remote(context, name)
    if file:
        with open(file, "w") as outfile:
            outfile.write(config.to_yaml())
    else:
        print(config.to_yaml())
