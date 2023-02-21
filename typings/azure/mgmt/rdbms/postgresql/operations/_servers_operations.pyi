from typing import Any
from azure.core.polling import LROPoller
from .. import models as _models

class ServersOperations:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def begin_update(
        self,
        resource_group_name: str,
        server_name: str,
        parameters: _models.ServerUpdateParameters,
        **kwargs: Any
    ) -> LROPoller[_models.Server]: ...
    def get(
        self, resource_group_name: str, server_name: str, **kwargs: Any
    ) -> _models.Server: ...
