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
    def __enter__(self): ...
    def __exit__(self, *args) -> None: ...
    def close(self) -> None: ...
    @property
    def url(self): ...
    @property
    def primary_endpoint(self): ...
    @property
    def primary_hostname(self): ...
    @property
    def secondary_endpoint(self): ...
    @property
    def secondary_hostname(self): ...
    @property
    def location_mode(self): ...
    @location_mode.setter
    def location_mode(self, value) -> None: ...
    @property
    def api_version(self): ...
