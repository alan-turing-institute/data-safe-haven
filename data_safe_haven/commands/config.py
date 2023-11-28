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
