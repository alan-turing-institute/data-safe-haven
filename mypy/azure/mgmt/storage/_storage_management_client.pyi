from typing import Any, Optional

from _typeshed import Incomplete
from azure.core.credentials import TokenCredential
from azure.profiles import KnownProfiles
from azure.profiles.multiapiclient import MultiApiClientMixin

class _SDKClient:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...

class StorageManagementClient(MultiApiClientMixin, _SDKClient):
    def __init__(
        self,
        credential: TokenCredential,
        subscription_id: str,
        api_version: Optional[str],
        base_url: str,
        profile: KnownProfiles,
        **kwargs: Any
    ) -> None: ...
