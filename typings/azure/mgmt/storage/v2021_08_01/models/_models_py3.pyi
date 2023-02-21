from typing import Any, Dict, List, Optional
import msrest.serialization
from _typeshed import Incomplete

class StorageAccountKey(msrest.serialization.Model):
    key_name: Incomplete
    value: str
    permissions: Incomplete
    creation_time: Incomplete
    def __init__(self, **kwargs: Any) -> None: ...

class StorageAccountListKeysResult(msrest.serialization.Model):
    keys: Optional[List[StorageAccountKey]]
    def __init__(self, **kwargs: Any) -> None: ...

class Resource(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...

class StorageAccount(TrackedResource):
    name: str
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...

class StorageAccountCreateParameters(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...

class TrackedResource(Resource):
    def __init__(
        self, *, location: str, tags: Optional[Dict[str, str]] = None, **kwargs: Any
    ) -> None: ...
