from collections.abc import Callable
from typing import Any

from typer import BadParameter

from data_safe_haven.functions.validators import (
    validate_aad_guid,
    validate_azure_vm_sku,
    validate_email_address,
    validate_ip_address,
    validate_timezone,
)


def typer_validator_factory(validator: Callable[[Any], Any]) -> Callable[[Any], Any]:
    def typer_validator(x: Any) -> Any:
        try:
            validator(x)
            return x
        except ValueError as exc:
            raise BadParameter(str(exc)) from exc

    return typer_validator


typer_validate_aad_guid = typer_validator_factory(validate_aad_guid)
typer_validate_email_address = typer_validator_factory(validate_email_address)
typer_validate_ip_address = typer_validator_factory(validate_ip_address)
typer_validate_azure_vm_sku = typer_validator_factory(validate_azure_vm_sku)
typer_validate_timezone = typer_validator_factory(validate_timezone)
