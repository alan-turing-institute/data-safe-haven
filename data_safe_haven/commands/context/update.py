from typing import Annotated, Optional

import typer

from data_safe_haven import validators
from data_safe_haven.context import (
    ContextSettings,
)

from .command_group import context_command_group


@context_command_group.command()
def update(
    admin_group: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="The ID of an Azure group containing all administrators.",
            callback=validators.typer_aad_guid,
        ),
    ] = None,
    location: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="The Azure location to deploy resources into.",
        ),
    ] = None,
    name: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="The human friendly name to give this Data Safe Haven deployment.",
        ),
    ] = None,
    subscription: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            help="The name of an Azure subscription to deploy resources into.",
        ),
    ] = None,
) -> None:
    """Update the selected context settings."""
    settings = ContextSettings.from_file()
    settings.update(
        admin_group_id=admin_group,
        location=location,
        name=name,
        subscription_name=subscription,
    )
    settings.write()
