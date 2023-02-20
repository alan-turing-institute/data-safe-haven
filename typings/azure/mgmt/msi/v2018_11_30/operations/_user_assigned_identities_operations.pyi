from typing import Any
from .. import models as _models

class UserAssignedIdentitiesOperations:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def create_or_update(
        self,
        resource_group_name: str,
        resource_name: str,
        parameters: _models.Identity,
        **kwargs: Any
    ) -> _models.Identity: ...
