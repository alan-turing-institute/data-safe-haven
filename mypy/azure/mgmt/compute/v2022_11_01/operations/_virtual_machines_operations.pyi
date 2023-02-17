from typing import Any
from azure.core.polling import LROPoller

class VirtualMachinesOperations:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def begin_restart(
        self, resource_group_name: str, vm_name: str, **kwargs: Any
    ) -> LROPoller[None]: ...
