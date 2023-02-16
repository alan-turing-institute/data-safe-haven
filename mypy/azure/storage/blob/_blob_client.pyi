from typing import IO, Any, AnyStr, Dict, Iterable, Optional, Union, overload
from _typeshed import Incomplete
from ...core.credentials import (
    AzureNamedKeyCredential,
    AzureSasCredential,
    TokenCredential,
)
from ._download import StorageStreamDownloader
from ._encryption import StorageEncryptionMixin
from ._models import BlobType
from ._shared.base_client import StorageAccountHostsMixin

class BlobClient(StorageAccountHostsMixin, StorageEncryptionMixin):
    container_name: Incomplete
    blob_name: Incomplete
    snapshot: Incomplete
    def __init__(
        self,
        account_url: str,
        container_name: str,
        blob_name: str,
        snapshot: Optional[Union[str, Dict[str, Any]]] = ...,
        credential: Optional[
            Union[
                str,
                Dict[str, str],
                AzureNamedKeyCredential,
                AzureSasCredential,
                "TokenCredential",
            ]
        ] = ...,
        **kwargs: Any
    ) -> None: ...
    def upload_blob(
        self,
        data: Union[bytes, str, Iterable[AnyStr], IO[AnyStr]],
        blob_type: Union[str, BlobType] = ...,
        length: Optional[int] = ...,
        metadata: Optional[Dict[str, str]] = ...,
        **kwargs
    ) -> Any: ...
    @overload
    def download_blob(
        self, offset: int = ..., length: int = ..., *, encoding: str, **kwargs
    ) -> StorageStreamDownloader[str]: ...
    @overload
    def download_blob(
        self, offset: int = ..., length: int = ..., *, encoding: None = ..., **kwargs
    ) -> StorageStreamDownloader[bytes]: ...
