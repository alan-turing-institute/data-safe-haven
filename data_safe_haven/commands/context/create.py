from data_safe_haven.context import (
    ContextSettings,
)
from data_safe_haven.context_infrastructure import ContextInfrastructure

from .command_group import context_command_group


@context_command_group.command()
def create() -> None:
    """Create Data Safe Haven context infrastructure."""
    context = ContextSettings.from_file().assert_context()
    context_infra = ContextInfrastructure(context)
    context_infra.create()
