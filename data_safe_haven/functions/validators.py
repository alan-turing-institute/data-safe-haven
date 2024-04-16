import ipaddress
import re
from collections.abc import Hashable
from typing import TypeVar

import fqdn
import pytz


def validate_aad_guid(aad_guid: str) -> str:
    if not re.match(
        r"^[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}$",
        aad_guid,
    ):
        msg = "Expected GUID, for example '10de18e7-b238-6f1e-a4ad-772708929203'."
        raise ValueError(msg)
    return aad_guid


def validate_azure_location(azure_location: str) -> str:
    if not re.match(r"^[a-z]+[0-9]?[a-z]*$", azure_location):
        msg = "Expected valid Azure location, for example 'uksouth'."
        raise ValueError(msg)
    return azure_location


def validate_azure_vm_sku(azure_vm_sku: str) -> str:
    if not re.match(r"^(Standard|Basic)_\w+$", azure_vm_sku):
        msg = "Expected valid Azure VM SKU, for example 'Standard_D2s_v4'."
        raise ValueError(msg)
    return azure_vm_sku


def validate_fqdn(domain: str) -> str:
    trial_fqdn = fqdn.FQDN(domain)
    if not trial_fqdn.is_valid:
        msg = "Expected valid fully qualified domain name, for example 'example.com'."
        raise ValueError(msg)
    return domain


def validate_email_address(email_address: str) -> str:
    if not re.match(r"^\S+@\S+$", email_address):
        msg = "Expected valid email address, for example 'sherlock@holmes.com'."
        raise ValueError(msg)
    return email_address


def validate_ip_address(ip_address: str) -> str:
    try:
        return str(ipaddress.ip_network(ip_address))
    except Exception as exc:
        msg = "Expected valid IPv4 address, for example '1.1.1.1'."
        raise ValueError(msg) from exc


def validate_timezone(timezone: str) -> str:
    if timezone not in pytz.all_timezones:
        msg = "Expected valid timezone, for example 'Europe/London'."
        raise ValueError(msg)
    return timezone


TH = TypeVar("TH", bound=Hashable)


def validate_unique_list(items: list[TH]) -> list[TH]:
    if len(items) != len(set(items)):
        msg = "All items must be unique."
        raise ValueError(msg)
    return items
