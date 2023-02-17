from typing import Any, Dict, Optional
from azure.core.polling import LROPoller
from ..models import (
    StorageAccount,
    StorageAccountCreateParameters,
    StorageAccountListKeysResult,
)

class StorageAccountsOperations:
    def list_keys(
        self,
        resource_group_name: str,
        account_name: str,
        expand: Optional[str] = ...,
        **kwargs: Any
    ) -> StorageAccountListKeysResult: ...
    def begin_create(
        self,
        resource_group_name: str,
        account_name: str,
        parameters: StorageAccountCreateParameters | Dict[str, Any],
        **kwargs: Any
    ) -> LROPoller[StorageAccount]: ...
