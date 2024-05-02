from collections.abc import Hashable
from typing import Annotated, TypeAlias, TypeVar

from pydantic import Field
from pydantic.functional_validators import AfterValidator

from data_safe_haven import validators

AzureShortName = Annotated[str, Field(min_length=1, max_length=24)]
AzureLongName = Annotated[str, Field(min_length=1, max_length=64)]
AzureLocation = Annotated[str, AfterValidator(validators.azure_location)]
AzureVmSku = Annotated[str, AfterValidator(validators.azure_vm_sku)]
EmailAddress = Annotated[str, AfterValidator(validators.email_address)]
Fqdn = Annotated[str, AfterValidator(validators.fqdn)]
Guid = Annotated[str, AfterValidator(validators.aad_guid)]
IpAddress = Annotated[str, AfterValidator(validators.ip_address)]
TimeZone = Annotated[str, AfterValidator(validators.timezone)]
TH = TypeVar("TH", bound=Hashable)
# type UniqueList[TH] = Annotated[list[TH], AfterValidator(validators.unique_list)]
# mypy doesn't support PEP695 type statements
UniqueList: TypeAlias = Annotated[  # noqa:UP040
    list[TH], AfterValidator(validators.unique_list)
]
