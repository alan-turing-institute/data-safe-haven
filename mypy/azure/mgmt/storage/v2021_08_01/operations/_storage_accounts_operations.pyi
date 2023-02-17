from typing import Any, Optional

from _typeshed import Incomplete

from ..models import StorageAccountListKeysResult

class StorageAccountsOperations:
    models: Incomplete
    def list_keys(
        self,
        resource_group_name: str,
        account_name: str,
        expand: Optional[str] = ...,
        **kwargs: Any
    ) -> StorageAccountListKeysResult: ...
