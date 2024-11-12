import ipaddress
import re
from collections.abc import Hashable
from typing import TypeVar

import pytz
from fqdn import FQDN


def aad_guid(aad_guid: str) -> str:
    if not re.match(
        r"^[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}$",
        aad_guid,
    ):
        msg = "Expected GUID, for example '10de18e7-b238-6f1e-a4ad-772708929203'."
        raise ValueError(msg)
    return aad_guid


def azure_location(azure_location: str) -> str:
    # Generate a list of locations with the following command:
    # `az account list-locations --query "[?metadata.regionType == 'Physical'].name"`
    locations = [
        "australiacentral",
        "australiacentral2",
        "australiaeast",
        "australiasoutheast",
        "brazilsouth",
        "brazilsoutheast",
        "brazilus",
        "canadacentral",
        "canadaeast",
        "centralindia",
        "centralus",
        "centraluseuap",
        "eastasia",
        "eastus",
        "eastus2",
        "eastus2euap",
        "eastusstg",
        "francecentral",
        "francesouth",
        "germanynorth",
        "germanywestcentral",
        "israelcentral",
        "italynorth",
        "japaneast",
        "japanwest",
        "jioindiacentral",
        "jioindiawest",
        "koreacentral",
        "koreasouth",
        "mexicocentral",
        "northcentralus",
        "northeurope",
        "norwayeast",
        "norwaywest",
        "polandcentral",
        "qatarcentral",
        "southafricanorth",
        "southafricawest",
        "southcentralus",
        "southeastasia",
        "southindia",
        "spaincentral",
        "swedencentral",
        "switzerlandnorth",
        "switzerlandwest",
        "uaecentral",
        "uaenorth",
        "uksouth",
        "ukwest",
        "westcentralus",
        "westeurope",
        "westindia",
        "westus",
        "westus2",
        "westus3",
    ]
    if azure_location not in locations:
        msg = "Expected valid Azure location, for example 'uksouth'."
        raise ValueError(msg)
    return azure_location


def azure_subscription_name(subscription_name: str) -> str:
    # https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules
    if not re.match(r"^[a-zA-Z0-9\- \[\]]+$", subscription_name):
        msg = "Azure subscription names can only contain alphanumeric characters, spaces and particular special characters."
        raise ValueError(msg)
    return subscription_name


def azure_vm_sku(azure_vm_sku: str) -> str:
    if not re.match(r"^(Standard|Basic)_\w+$", azure_vm_sku):
        msg = "Expected valid Azure VM SKU, for example 'Standard_D2s_v4'."
        raise ValueError(msg)
    return azure_vm_sku


def fqdn(domain: str) -> str:
    trial_fqdn = FQDN(domain)
    if not trial_fqdn.is_valid:
        msg = "Expected valid fully qualified domain name, for example 'example.com'."
        raise ValueError(msg)
    return domain


def email_address(email_address: str) -> str:
    if not re.match(r"^\S+@\S+$", email_address):
        msg = "Expected valid email address, for example 'sherlock@holmes.com'."
        raise ValueError(msg)
    return email_address


def entra_group_name(entra_group_name: str) -> str:
    if entra_group_name.startswith(" "):
        msg = "Entra group names cannot start with a space."
        raise ValueError(msg)
    return entra_group_name


def ip_address(ip_address: str) -> str:
    try:
        return str(ipaddress.ip_network(ip_address))
    except Exception as exc:
        msg = "Expected valid IPv4 address, for example '1.1.1.1'."
        raise ValueError(msg) from exc


def safe_string(safe_string: str) -> str:
    if not re.match(r"^[a-zA-Z0-9_-]+$", safe_string) or not safe_string:
        msg = "Expected valid string containing only letters, numbers, hyphens and underscores."
        raise ValueError(msg)
    return safe_string


def safe_sre_name(safe_sre_name: str) -> str:
    if not re.match(r"^[a-z0-9_-]+$", safe_sre_name) or not safe_sre_name:
        msg = "Expected valid string containing only lowercase letters, numbers, hyphens and underscores."
        raise ValueError(msg)
    return safe_sre_name


def timezone(timezone: str) -> str:
    if timezone not in pytz.all_timezones:
        msg = "Expected valid timezone, for example 'Europe/London'."
        raise ValueError(msg)
    return timezone


TH = TypeVar("TH", bound=Hashable)


def unique_list(items: list[TH]) -> list[TH]:
    if len(items) != len(set(items)):
        msg = "All items must be unique."
        raise ValueError(msg)
    return items
