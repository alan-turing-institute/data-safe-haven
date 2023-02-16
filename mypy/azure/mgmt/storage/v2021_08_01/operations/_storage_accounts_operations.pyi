from ..models import StorageAccountListKeysResult
from _typeshed import Incomplete
from typing import Any, Optional

class StorageAccountsOperations:
    models: Incomplete
    def list_keys(
        self,
        resource_group_name: str,
        account_name: str,
        expand: Optional[str] = ...,
        **kwargs: Any
    ) -> StorageAccountListKeysResult: ...
