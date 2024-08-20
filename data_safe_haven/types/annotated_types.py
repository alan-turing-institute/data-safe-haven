from collections.abc import Hashable
from typing import Annotated, TypeAlias, TypeVar

from annotated_types import Ge
from pydantic import Field
from pydantic.functional_validators import AfterValidator

from data_safe_haven import validators

AzureLocation = Annotated[str, AfterValidator(validators.azure_location)]
AzurePremiumFileShareSize = Annotated[int, Ge(100)]
AzureShortName = Annotated[str, Field(min_length=1, max_length=24)]
AzureSubscriptionName = Annotated[
    str,
    Field(min_length=1, max_length=80),
    AfterValidator(validators.azure_subscription_name),
]
AzureVmSku = Annotated[str, AfterValidator(validators.azure_vm_sku)]
EmailAddress = Annotated[str, AfterValidator(validators.email_address)]
EntraGroupName = Annotated[str, AfterValidator(validators.entra_group_name)]
Fqdn = Annotated[str, AfterValidator(validators.fqdn)]
Guid = Annotated[str, AfterValidator(validators.aad_guid)]
IpAddress = Annotated[str, AfterValidator(validators.ip_address)]
SafeString = Annotated[str, AfterValidator(validators.safe_string)]
TimeZone = Annotated[str, AfterValidator(validators.timezone)]
TH = TypeVar("TH", bound=Hashable)
# type UniqueList[TH] = Annotated[list[TH], AfterValidator(validators.unique_list)]
# mypy doesn't support PEP695 type statements
UniqueList: TypeAlias = Annotated[  # noqa:UP040
    list[TH], AfterValidator(validators.unique_list)
]
