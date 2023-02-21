from typing import Any, Optional
from azure.core.credentials import TokenCredential
from azure.profiles import KnownProfiles
from azure.profiles.multiapiclient import MultiApiClientMixin
from .v2021_04_01.operations import ResourceGroupsOperations

class _SDKClient(object):
    def __init__(self, *args: Any, **kwargs: Any): ...

class ResourceManagementClient(MultiApiClientMixin, _SDKClient):
    def __init__(
        self,
        credential: TokenCredential,
        subscription_id: str,
        api_version: Optional[str] = ...,
        base_url: Optional[str] = ...,
        profile: Optional[KnownProfiles] = ...,
        **kwargs: Any
    ) -> None: ...
    @property
    def resource_groups(self) -> ResourceGroupsOperations: ...
