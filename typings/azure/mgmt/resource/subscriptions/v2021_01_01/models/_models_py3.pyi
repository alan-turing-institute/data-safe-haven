from typing import Any, Optional, Union
import msrest.serialization
from azure.core.exceptions import HttpResponseError as HttpResponseError
from ._subscription_client_enums import ResourceNameStatus

class CheckResourceNameResult(msrest.serialization.Model):
    def __init__(
        self,
        *,
        name: Optional[str] = ...,
        type: Optional[str] = ...,
        status: Optional[Union[str, ResourceNameStatus]] = ...,
        **kwargs: Any,
    ) -> None: ...

class ResourceName(msrest.serialization.Model):
    def __init__(self, *, name: str, type: str, **kwargs: Any) -> None: ...

class Subscription(msrest.serialization.Model):
    id: str
    subscription_id: str
    display_name: str
    tenant_id: str
    state: str
    subscription_policies: SubscriptionPolicies
    authorization_source: str
    def __init__(
        self,
        *,
        subscription_policies: Optional[SubscriptionPolicies] = ...,
        authorization_source: Optional[str] = ...,
        **kwargs: Any,
    ) -> None: ...

class SubscriptionPolicies(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...
