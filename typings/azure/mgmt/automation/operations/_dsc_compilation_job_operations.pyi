from typing import Any
from .. import models as _models
from azure.core.polling import LROPoller

class DscCompilationJobOperations(object):
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def begin_create(
        self,
        resource_group_name: str,
        automation_account_name: str,
        compilation_job_name: str,
        parameters: _models.DscCompilationJobCreateParameters,
        **kwargs: Any,
    ) -> LROPoller[_models.DscCompilationJob]: ...
    def get(
        self,
        resource_group_name: str,
        automation_account_name: str,
        compilation_job_name: str,
        **kwargs: Any,
    ) -> _models.DscCompilationJob: ...
