from typing import Any, Dict, List, Optional
from _typeshed import Incomplete
from .token_cache import TokenCache

class ClientApplication(object):
    def __init__(
        self,
        client_id: str,
        authority: Optional[str] = None,
        client_credential: Optional[str | Dict[Any, Any]] = None,
        client_claims: Optional[Dict[str, Any]] = None,
        validate_authority: bool = True,
        token_cache: Optional[TokenCache] = None,
        http_client: Optional[Incomplete] = None,
        verify: bool = True,
        proxies: Optional[Incomplete] = None,
        timeout: Optional[Incomplete] = None,
        app_name: Optional[str] = None,
        app_version: Optional[Incomplete] = None,
        client_capabilities: Optional[List[str]] = None,
        azure_region: Optional[str] = None,
        exclude_scopes: Optional[List[str]] = None,
        http_cache: Optional[Dict[Any, Any]] = None,
        instance_discovery: Optional[bool] = None,
        allow_broker: Optional[bool] = None,
    ) -> None: ...
    def get_accounts(self, username: Optional[str] = None) -> List[Dict[str, Any]]: ...
    def acquire_token_silent(
        self,
        scopes: List[str],
        account: Optional[Dict[str, Any]],
        authority: Optional[Incomplete] = None,
        force_refresh: Optional[bool] = False,
        claims_challenge: Optional[str] = None,
        **kwargs: Any
    ) -> (dict[str, Any] | None): ...

class PublicClientApplication(ClientApplication):
    def __init__(
        self,
        client_id: str,
        client_credential: Optional[str | Dict[Any, Any]] = None,
        **kwargs: Any
    ): ...

class ConfidentialClientApplication(ClientApplication):
    pass
