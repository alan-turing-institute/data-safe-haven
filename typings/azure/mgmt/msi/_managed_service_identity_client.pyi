from typing import Any, Optional
from azure.core.credentials import TokenCredential
from azure.profiles import KnownProfiles
from azure.profiles.multiapiclient import MultiApiClientMixin
from .v2018_11_30.operations import UserAssignedIdentitiesOperations

class _SDKClient:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...

class ManagedServiceIdentityClient(MultiApiClientMixin, _SDKClient):
    def __init__(
        self,
        credential: TokenCredential,
        subscription_id: str,
        api_version: Optional[str] = None,
        base_url: Optional[str] = ...,
        profile: Optional[KnownProfiles] = ...,
        **kwargs: Any
    ) -> None: ...
    @property
    def user_assigned_identities(self) -> UserAssignedIdentitiesOperations: ...
