from typing import Any, Dict, Optional, Union

from _typeshed import Incomplete
from azure.core.credentials import (
    AzureNamedKeyCredential,
    AzureSasCredential,
    TokenCredential,
)

class StorageAccountHostsMixin:
    scheme: Incomplete
    account_name: Incomplete
    credential: Incomplete
    def __init__(
        self,
        parsed_url: Any,
        service: str,
        credential: Optional[
            Union[
                str,
                Dict[str, str],
                AzureNamedKeyCredential,
                AzureSasCredential,
                TokenCredential,
            ]
        ] = ...,
        **kwargs: Any
    ) -> None: ...
