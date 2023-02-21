from typing import Any, Dict, Optional
import msrest.serialization

class ResourceGroup(msrest.serialization.Model):
    id: str
    name: str
    type: str
    properties: ResourceGroupProperties
    location: str
    managed_by: str
    tags: Dict[str, str]
    def __init__(
        self,
        *,
        location: str,
        properties: Optional[ResourceGroupProperties] = None,
        managed_by: Optional[str] = None,
        tags: Optional[Dict[str, str]] = None,
        **kwargs: Any
    ) -> None: ...

class ResourceGroupProperties(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...
