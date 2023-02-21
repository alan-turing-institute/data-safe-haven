from typing import Any, Optional
from azure.core.credentials import TokenCredential
from .operations import FirewallRulesOperations, ServersOperations

class PostgreSQLManagementClient:
    def __init__(
        self,
        credential: TokenCredential,
        subscription_id: str,
        base_url: Optional[str] = ...,
        **kwargs: Any
    ) -> None: ...
    @property
    def firewall_rules(self) -> FirewallRulesOperations: ...
    @property
    def servers(self) -> ServersOperations: ...
