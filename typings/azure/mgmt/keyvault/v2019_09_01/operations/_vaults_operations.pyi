from typing import Any, List, Optional
from azure.core.polling import LROPoller
from .. import models as _models

class VaultsOperations:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def begin_create_or_update(
        self,
        resource_group_name: str,
        vault_name: str,
        parameters: _models.VaultCreateOrUpdateParameters,
        **kwargs: Any
    ) -> LROPoller[_models.Vault]: ...
    def list(self, top: Optional[int] = ..., **kwargs: Any) -> List[_models.Vault]: ...
