from typing import Annotated

from pydantic import Field
from pydantic.functional_validators import AfterValidator

from data_safe_haven.functions import (
    validate_aad_guid,
    validate_azure_location,
    validate_azure_vm_sku,
    validate_email_address,
    validate_ip_address,
    validate_timezone,
)

AzureShortName = Annotated[str, Field(min_length=1, max_length=24)]
AzureLongName = Annotated[str, Field(min_length=1, max_length=64)]
AzureLocation = Annotated[str, AfterValidator(validate_azure_location)]
AzureVmSku = Annotated[str, AfterValidator(validate_azure_vm_sku)]
EmailAdress = Annotated[str, AfterValidator(validate_email_address)]
Guid = Annotated[str, AfterValidator(validate_aad_guid)]
IpAddress = Annotated[str, AfterValidator(validate_ip_address)]
TimeZone = Annotated[str, AfterValidator(validate_timezone)]
