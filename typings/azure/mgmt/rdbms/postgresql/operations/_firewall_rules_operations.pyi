from typing import Any
from azure.core.polling import LROPoller
from .. import models as _models

class FirewallRulesOperations:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def begin_create_or_update(
        self,
        resource_group_name: str,
        server_name: str,
        firewall_rule_name: str,
        parameters: _models.FirewallRule,
        **kwargs: Any
    ) -> LROPoller[_models.FirewallRule]: ...
    def begin_delete(
        self,
        resource_group_name: str,
        server_name: str,
        firewall_rule_name: str,
        **kwargs: Any
    ) -> LROPoller[None]: ...
