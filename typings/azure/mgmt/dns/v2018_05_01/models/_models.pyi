from typing import Any
import msrest.serialization

class RecordSet(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...

class TxtRecord(msrest.serialization.Model):
    value: str
    def __init__(self, **kwargs: Any) -> None: ...
