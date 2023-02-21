from typing import Any
from .. import models as _models

class ContainersOperations:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def execute_command(
        self,
        resource_group_name: str,
        container_group_name: str,
        container_name: str,
        container_exec_request: _models.ContainerExecRequest,
        **kwargs: Any
    ) -> _models.ContainerExecResponse: ...
