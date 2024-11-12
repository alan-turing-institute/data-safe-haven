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
typer_azure_subscription_name = typer_validator_factory(
    validators.azure_subscription_name
)
typer_azure_vm_sku = typer_validator_factory(validators.azure_vm_sku)
typer_email_address = typer_validator_factory(validators.email_address)
typer_entra_group_name = typer_validator_factory(validators.entra_group_name)
typer_fqdn = typer_validator_factory(validators.fqdn)
typer_ip_address = typer_validator_factory(validators.ip_address)
typer_safe_sre_name = typer_validator_factory(validators.safe_sre_name)
typer_safe_string = typer_validator_factory(validators.safe_string)
typer_timezone = typer_validator_factory(validators.timezone)
