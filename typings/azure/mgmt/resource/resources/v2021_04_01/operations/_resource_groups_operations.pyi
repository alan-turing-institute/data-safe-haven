from typing import Any, List, Optional
from azure.core.polling import LROPoller
from .. import models as _models

class ResourceGroupsOperations(object):
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def begin_delete(
        self,
        resource_group_name: str,
        force_deletion_types: Optional[str] = None,
        **kwargs: Any
    ) -> LROPoller[None]: ...
    def create_or_update(
        self, resource_group_name: str, parameters: _models.ResourceGroup, **kwargs: Any
    ) -> _models.ResourceGroup: ...
    def list(
        self, filter: Optional[str] = None, top: Optional[int] = None, **kwargs: Any
    ) -> List[_models.ResourceGroup]: ...
