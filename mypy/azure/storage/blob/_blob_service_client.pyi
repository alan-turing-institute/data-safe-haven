from typing import Any, Dict, Optional, Union

from ...core.credentials import (
    AzureNamedKeyCredential,
    AzureSasCredential,
    TokenCredential,
)
from ._blob_client import BlobClient
from ._encryption import StorageEncryptionMixin
from ._models import BlobProperties, ContainerProperties
from ._shared.base_client import StorageAccountHostsMixin

class BlobServiceClient(StorageAccountHostsMixin, StorageEncryptionMixin):
    def __init__(
        self,
        account_url: str,
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
    @classmethod
    def from_connection_string(
        cls,
        conn_str: str,
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
    ) -> "BlobServiceClient": ...
    def get_blob_client(
        self,
        container: Union[ContainerProperties, str],
        blob: Union[BlobProperties, str],
        snapshot: Optional[Union[Dict[str, Any], str]] = ...,
    ) -> BlobClient: ...
