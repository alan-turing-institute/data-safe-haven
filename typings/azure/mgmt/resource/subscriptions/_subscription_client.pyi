from azure.core.credentials import TokenCredential
from azure.profiles import KnownProfiles
from azure.profiles.multiapiclient import MultiApiClientMixin
from typing import Any, Optional
from ._operations_mixin import SubscriptionClientOperationsMixin
from .v2021_01_01.operations import SubscriptionsOperations

class _SDKClient:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...

class SubscriptionClient(
    SubscriptionClientOperationsMixin, MultiApiClientMixin, _SDKClient
):
    def __init__(
        self,
        credential: TokenCredential,
        api_version: Optional[str] = None,
        base_url: Optional[str] = ...,
        profile: Optional[KnownProfiles] = ...,
        **kwargs: Any
    ) -> None: ...
    @property
    def subscriptions(self) -> SubscriptionsOperations: ...
