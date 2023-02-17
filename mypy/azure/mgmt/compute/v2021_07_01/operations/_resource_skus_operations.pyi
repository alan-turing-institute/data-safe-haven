from typing import Any, Iterable, Optional

from ..models import ResourceSku

class ResourceSkusOperations:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def list(
        self,
        filter: Optional[str] = None,
        include_extended_locations: Optional[str] = None,
        **kwargs: Any
    ) -> Iterable[ResourceSku]: ...
