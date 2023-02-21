from typing import Any
from azure.core.polling import LROPoller
from .. import models as _models

class ContainerGroupsOperations(object):
    def __init__(
        self,
        *args: Any,
        **kwargs: Any,
    ) -> None: ...
    def get(
        self, resource_group_name: str, container_group_name: str, **kwargs: Any
    ) -> _models.ContainerGroup: ...
    def begin_restart(
        self, resource_group_name: str, container_group_name: str, **kwargs: Any
    ) -> LROPoller[None]: ...
