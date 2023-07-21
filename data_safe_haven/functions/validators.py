# Standard library imports
import ipaddress
import re
from typing import Optional

# Third-party imports
import pytz
import typer


def validate_aad_guid(aad_guid: Optional[str]) -> Optional[str]:
    if aad_guid is not None:
        if not re.match(
            r"^[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}$",
            aad_guid,
        ):
            raise typer.BadParameter(
                "Expected GUID, for example '10de18e7-b238-6f1e-a4ad-772708929203'"
            )
    return aad_guid


def validate_azure_vm_sku(azure_vm_sku: Optional[str]) -> Optional[str]:
    if azure_vm_sku is not None:
        if not re.match(r"^(Standard|Basic)_\w+$", azure_vm_sku):
            raise typer.BadParameter(
                "Expected valid Azure VM Sku, for example 'Standard_D2s_v4'"
            )
    return azure_vm_sku


def validate_email_address(email_address: Optional[str]) -> Optional[str]:
    if email_address is not None:
        if not re.match(r"^\S+@\S+$", email_address):
            raise typer.BadParameter(
                "Expected valid email address, for example 'sherlock@holmes.com'"
            )
    return email_address


def validate_ip_address(
    ip_address: Optional[str],
) -> Optional[str]:
    try:
        if ip_address:
            return str(ipaddress.ip_network(ip_address))
        return None
    except Exception:
        raise typer.BadParameter("Expected valid IPv4 address, for example '1.1.1.1'")


def validate_azure_location(location: Optional[str]) -> Optional[str]:
    if not location:
        return None
    if location in (
        "asia",
        "asiapacific",
        "australia",
        "australiacentral",
        "australiacentral2",
        "australiaeast",
        "australiasoutheast",
        "brazil",
        "brazilsouth",
        "brazilsoutheast",
        "brazilus",
        "canada",
        "canadacentral",
        "canadaeast",
        "centralindia",
        "centralus",
        "centraluseuap",
        "centralusstage",
        "devfabric",
        "eastasia",
        "eastasiastage",
        "eastus",
        "eastus2",
        "eastus2euap",
        "eastus2stage",
        "eastusstage",
        "eastusstg",
        "europe",
        "france",
        "francecentral",
        "francesouth",
        "germany",
        "germanynorth",
        "germanywestcentral",
        "global",
        "india",
        "japan",
        "japaneast",
        "japanwest",
        "jioindiacentral",
        "jioindiawest",
        "korea",
        "koreacentral",
        "koreasouth",
        "northcentralus",
        "northcentralusstage",
        "northeurope",
        "norway",
        "norwayeast",
        "norwaywest",
        "qatarcentral",
        "singapore",
        "southafrica",
        "southafricanorth",
        "southafricawest",
        "southcentralus",
        "southcentralusstage",
        "southeastasia",
        "southeastasiastage",
        "southindia",
        "swedencentral",
        "switzerland",
        "switzerlandnorth",
        "switzerlandwest",
        "uae",
        "uaecentral",
        "uaenorth",
        "uk",
        "uksouth",
        "ukwest",
        "unitedstates",
        "unitedstateseuap",
        "westcentralus",
        "westeurope",
        "westindia",
        "westus",
        "westus2",
        "westus2stage",
        "westus3",
        "westusstage",
    ):
        return location
    raise typer.BadParameter("Expected valid Azure location, for example 'uksouth'")


def validate_timezone(timezone: Optional[str]) -> Optional[str]:
    if timezone is not None:
        if timezone not in pytz.all_timezones:
            raise typer.BadParameter(
                "Expected valid timezone, for example 'Europe/London'"
            )
    return timezone
