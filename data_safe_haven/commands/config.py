"""Command group and entrypoints for managing DSH configuration"""

from pathlib import Path
from typing import Annotated, Optional

import typer
from rich import print

from data_safe_haven.config import Config
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
    if file:
        with open(file, "w") as outfile:
            outfile.write(config.to_yaml())
    else:
        print(config.to_yaml())


@config_command_group.command()
def upload(
    file: Annotated[Path, typer.Argument(help="Path to configuration file")]
) -> None:
    """Upload a configuration to the Data Safe Haven context"""
    context = ContextSettings.from_file().assert_context()
    logger = LoggingSingleton()

    # Create configuration object from file
    with open(file) as config_file:
        config_yaml = config_file.read()
    config = Config.from_yaml(config_yaml)

    # Present diff to user
    if Config.remote_exists(context):
        if diff := config.remote_yaml_diff(context):
            print(diff)
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
def show(
    file: Annotated[
        Optional[Path],  # noqa: UP007
        typer.Option(help="File path to write configuration template to."),
    ] = None
) -> None:
    """Print the configuration for the selected Data Safe Haven context"""
    context = ContextSettings.from_file().assert_context()
    config = Config.from_remote(context)
    if file:
        with open(file, "w") as outfile:
            outfile.write(config.to_yaml())
    else:
        print(config.to_yaml())
