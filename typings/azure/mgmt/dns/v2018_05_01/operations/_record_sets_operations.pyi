from typing import Any, Optional, Union
from .. import models as _models

class RecordSetsOperations:
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def create_or_update(
        self,
        resource_group_name: str,
        zone_name: str,
        relative_record_set_name: str,
        record_type: Union[str, _models.RecordType],
        parameters: _models.RecordSet,
        if_match: Optional[str] = ...,
        if_none_match: Optional[str] = ...,
        **kwargs: Any
    ) -> _models.RecordSet: ...
    def delete(
        self,
        resource_group_name: str,
        zone_name: str,
        relative_record_set_name: str,
        record_type: Union[str, _models.RecordType],
        if_match: Optional[str] = ...,
        **kwargs: Any
    ) -> None: ...
