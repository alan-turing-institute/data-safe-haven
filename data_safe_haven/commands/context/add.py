from typing import Annotated

import typer

from data_safe_haven import validators
from data_safe_haven.context import (
    Context,
    ContextSettings,
)

from .command_group import context_command_group


@context_command_group.command()
def add(
    key: Annotated[str, typer.Argument(help="Key of the context to add.")],
    admin_group: Annotated[
        str,
        typer.Option(
            help="The ID of an Azure group containing all administrators.",
            callback=validators.typer_aad_guid,
        ),
    ],
    location: Annotated[
        str,
        typer.Option(
            help="The Azure location to deploy resources into.",
        ),
    ],
    name: Annotated[
        str,
        typer.Option(
            help="The human friendly name to give this Data Safe Haven deployment.",
        ),
    ],
    subscription: Annotated[
        str,
        typer.Option(
            help="The name of an Azure subscription to deploy resources into.",
        ),
    ],
) -> None:
    """Add a new context to the context list."""
    if ContextSettings.default_config_file_path().exists():
        settings = ContextSettings.from_file()
        settings.add(
            key=key,
            admin_group_id=admin_group,
            location=location,
            name=name,
            subscription_name=subscription,
        )
    else:
        # Bootstrap context settings file
        settings = ContextSettings(
            selected=key,
            contexts={
                key: Context(
                    admin_group_id=admin_group,
                    location=location,
                    name=name,
                    subscription_name=subscription,
                )
            },
        )
    settings.write()
