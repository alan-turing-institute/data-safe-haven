"""Command group and entrypoints for managing DSH configuration"""
from pathlib import Path
from typing import Annotated, Optional

import typer
from rich import print

from data_safe_haven.config import Config, ContextSettings

config_command_group = typer.Typer()


@config_command_group.command()
def template(
    file: Annotated[
        Optional[Path],
        typer.Option(help="File path to write configuration template to.")
    ] = None
) -> None:
    """Write a template Data Safe Haven configuration."""
    context = ContextSettings.from_file()
    config = Config.template(context)
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
    context = ContextSettings.from_file().context
    with open(file) as config_file:
        config_yaml = config_file.read()
    config = Config.from_yaml(context, config_yaml)
    config.upload()
