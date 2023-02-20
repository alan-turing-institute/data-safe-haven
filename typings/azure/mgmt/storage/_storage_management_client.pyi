from typing import Any, Optional

from azure.core.credentials import TokenCredential
from azure.identity import DefaultAzureCredential
from azure.profiles import KnownProfiles
from azure.profiles.multiapiclient import MultiApiClientMixin

from .v2021_08_01.operations import StorageAccountsOperations

class _SDKClient:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...

class StorageManagementClient(MultiApiClientMixin, _SDKClient):
    def __init__(
        self,
        credential: TokenCredential | DefaultAzureCredential,
        subscription_id: str,
        api_version: Optional[str] = None,
        base_url: Optional[str] = ...,
        profile: Optional[KnownProfiles] = ...,
        **kwargs: Any
    ) -> None: ...
    @property
    def storage_accounts(self) -> StorageAccountsOperations: ...
