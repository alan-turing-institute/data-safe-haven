from collections.abc import Hashable
from typing import Annotated, TypeAlias, TypeVar

from pydantic import Field
from pydantic.functional_validators import AfterValidator

from data_safe_haven.functions.validators import (
    validate_aad_guid,
    validate_azure_location,
    validate_azure_vm_sku,
    validate_email_address,
    validate_fqdn,
    validate_ip_address,
    validate_timezone,
    validate_unique_list,
)

AzureShortName = Annotated[str, Field(min_length=1, max_length=24)]
AzureLongName = Annotated[str, Field(min_length=1, max_length=64)]
AzureLocation = Annotated[str, AfterValidator(validate_azure_location)]
AzureVmSku = Annotated[str, AfterValidator(validate_azure_vm_sku)]
EmailAdress = Annotated[str, AfterValidator(validate_email_address)]
Fqdn = Annotated[str, AfterValidator(validate_fqdn)]
Guid = Annotated[str, AfterValidator(validate_aad_guid)]
IpAddress = Annotated[str, AfterValidator(validate_ip_address)]
TimeZone = Annotated[str, AfterValidator(validate_timezone)]
TH = TypeVar("TH", bound=Hashable)
# type UniqueList[TH] = Annotated[list[TH], AfterValidator(validate_unique_list)]
# mypy doesn't support PEP695 type statements
UniqueList: TypeAlias = Annotated[  # noqa:UP040
    list[TH], AfterValidator(validate_unique_list)
]
