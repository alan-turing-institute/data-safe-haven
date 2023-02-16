from typing import Any, NamedTuple, Optional
from _typeshed import Incomplete
from typing_extensions import Protocol

class AccessToken(NamedTuple):
    token: str
    expires_on: int

class TokenCredential(Protocol):
    def get_token(
        self,
        *scopes: str,
        claims: Optional[str] = ...,
        tenant_id: Optional[str] = ...,
        **kwargs: Any
    ) -> AccessToken: ...

class AzureNamedKey(NamedTuple):
    name: Incomplete
    key: Incomplete

class AzureKeyCredential:
    def __init__(self, key: str) -> None: ...
    @property
    def key(self) -> str: ...
    def update(self, key: str) -> None: ...

class AzureSasCredential:
    def __init__(self, signature: str) -> None: ...
    @property
    def signature(self) -> str: ...
    def update(self, signature: str) -> None: ...

class AzureNamedKeyCredential:
    def __init__(self, name: str, key: str) -> None: ...
    @property
    def named_key(self) -> AzureNamedKey: ...
    def update(self, name: str, key: str) -> None: ...
