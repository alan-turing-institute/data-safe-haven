from typing import Any, Dict, Optional
import msrest.serialization

class Resource(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...

class TrackedResource(Resource):
    def __init__(
        self, *, location: str, tags: Optional[Dict[str, str]] = None, **kwargs
    ) -> None: ...

class Identity(TrackedResource):
    def __init__(
        self, *, location: str, tags: Optional[Dict[str, str]] = None, **kwargs: Any
    ) -> None: ...
