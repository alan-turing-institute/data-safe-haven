from typing import Any, Dict, Optional
import msrest.serialization

class Resource(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...

class TrackedResource(Resource):
    def __init__(
        self, *, location: str, tags: Optional[Dict[str, str]] = None, **kwargs
    ) -> None: ...

class Identity(TrackedResource):
    client_id: str
    id: str
    location: str
    name: str
    principal_id: str
    tags: Dict[str, str]
    tenant_id: str
    type: str
    def __init__(
        self, *, location: str, tags: Optional[Dict[str, str]] = None, **kwargs: Any
    ) -> None: ...
