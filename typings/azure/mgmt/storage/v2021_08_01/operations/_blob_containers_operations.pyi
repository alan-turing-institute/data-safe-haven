from typing import Any
from .. import models as _models

class BlobContainersOperations:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def create(
        self,
        resource_group_name: str,
        account_name: str,
        container_name: str,
        blob_container: _models.BlobContainer,
        **kwargs: Any
    ) -> _models.BlobContainer: ...
