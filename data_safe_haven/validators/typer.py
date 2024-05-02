from collections.abc import Callable
from typing import Any

from typer import BadParameter

from . import validators


def typer_validator_factory(validator: Callable[[Any], Any]) -> Callable[[Any], Any]:
    """Factory to create validation functions for Typer from Pydantic validators"""

    def typer_validator(x: Any) -> Any:
        # Return unused optional arguments
        if x is None:
            return x

        # Validate input, catching ValueError to raise Typer Exception
        try:
            validator(x)
            return x
        except ValueError as exc:
            raise BadParameter(str(exc)) from exc

    return typer_validator


typer_aad_guid = typer_validator_factory(validators.aad_guid)
typer_azure_vm_sku = typer_validator_factory(validators.azure_vm_sku)
typer_email_address = typer_validator_factory(validators.email_address)
typer_ip_address = typer_validator_factory(validators.ip_address)
typer_timezone = typer_validator_factory(validators.timezone)
