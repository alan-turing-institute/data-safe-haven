from typing import List, Optional
import msrest.serialization
from _typeshed import Incomplete

class StorageAccountKey(msrest.serialization.Model):
    key_name: Incomplete
    value: str
    permissions: Incomplete
    creation_time: Incomplete
    def __init__(self, **kwargs) -> None: ...

class StorageAccountListKeysResult(msrest.serialization.Model):
    keys: Optional[List[StorageAccountKey]]
    def __init__(self, **kwargs) -> None: ...
