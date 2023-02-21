from typing import Any, Optional
from .v2021_01_01.models import ResourceName, CheckResourceNameResult

class SubscriptionClientOperationsMixin:
    def check_resource_name(
        self, resource_name_definition: Optional[ResourceName] = ..., **kwargs: Any
    ) -> CheckResourceNameResult: ...
