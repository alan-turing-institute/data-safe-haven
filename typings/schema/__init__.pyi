from typing import Any


class SchemaError(Exception):
    ...


class Schema:
    def __init__(self, schema: dict[Any, Any]) -> None: ...
    def validate(self, data: Any) -> Any: ...
