from typing import Any, Optional
from azure.core.credentials import TokenCredential
from azure.profiles import KnownProfiles
from azure.profiles.multiapiclient import MultiApiClientMixin
from .v2019_09_01.operations import VaultsOperations

class _SDKClient:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...

class KeyVaultManagementClient(MultiApiClientMixin, _SDKClient):
    def __init__(
        self,
        credential: TokenCredential,
        subscription_id: str,
        api_version: Optional[str] = ...,
        base_url: Optional[str] = ...,
        profile: KnownProfiles = ...,
        **kwargs: Any
    ) -> None: ...
    @property
    def vaults(self) -> VaultsOperations: ...
