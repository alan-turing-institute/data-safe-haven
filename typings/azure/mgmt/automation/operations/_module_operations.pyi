from typing import Any, Iterable
from .. import models as _models

class ModuleOperations(object):
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def list_by_automation_account(
        self,
        resource_group_name: str,
        automation_account_name: str,
        **kwargs: Any,
    ) -> Iterable[_models.Module]: ...
