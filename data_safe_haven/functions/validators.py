import ipaddress
import re
from typing import Any

import pytz
import typer


def validate_aad_guid(aad_guid: str | None) -> str | None:
    if aad_guid is not None:
        if not re.match(
            r"^[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}$",
            aad_guid,
        ):
            msg = "Expected GUID, for example '10de18e7-b238-6f1e-a4ad-772708929203'."
            raise typer.BadParameter(msg)
    return aad_guid


def validate_azure_location(azure_location: str | None) -> str | None:
    if azure_location is not None:
        if not re.match(r"^[a-z]+[0-9]?[a-z]*$", azure_location):
            msg = "Expected valid Azure location, for example 'uksouth'."
            raise typer.BadParameter(msg)
    return azure_location


def validate_azure_vm_sku(azure_vm_sku: str | None) -> str | None:
    if azure_vm_sku is not None:
        if not re.match(r"^(Standard|Basic)_\w+$", azure_vm_sku):
            msg = "Expected valid Azure VM SKU, for example 'Standard_D2s_v4'."
            raise typer.BadParameter(msg)
    return azure_vm_sku


def validate_email_address(email_address: str | None) -> str | None:
    if email_address is not None:
        if not re.match(r"^\S+@\S+$", email_address):
            msg = "Expected valid email address, for example 'sherlock@holmes.com'."
            raise typer.BadParameter(msg)
    return email_address


def validate_ip_address(
    ip_address: str | None,
) -> str | None:
    try:
        if ip_address:
            return str(ipaddress.ip_network(ip_address))
        return None
    except Exception as exc:
        msg = "Expected valid IPv4 address, for example '1.1.1.1'."
        raise typer.BadParameter(msg) from exc


def validate_non_empty_string(value: Any) -> str:
    try:
        return validate_string_length(value, min_length=1)
    except Exception as exc:
        msg = "Expected non-empty string."
        raise typer.BadParameter(msg) from exc


def validate_string_length(
    value: Any, min_length: int | None = None, max_length: int | None = None
) -> str:
    if isinstance(value, str):
        if min_length and len(value) < min_length:
            msg = f"Expected string with minimum length {min_length}."
            raise typer.BadParameter(msg)
        if max_length and len(value) > max_length:
            msg = f"Expected string with maximum length {max_length}."
            raise typer.BadParameter(msg)
        return str(value)
    msg = "Expected string."
    raise typer.BadParameter(msg)


def validate_timezone(timezone: str | None) -> str | None:
    if timezone is not None:
        if timezone not in pytz.all_timezones:
            msg = "Expected valid timezone, for example 'Europe/London'."
            raise typer.BadParameter(msg)
    return timezone


def validate_type(value: Any, type_: type) -> Any:
    if not isinstance(value, type_):
        msg = f"Expected type '{type_.__name__}' but received '{type(value).__name__}'."
        raise typer.BadParameter(msg)
    return value
