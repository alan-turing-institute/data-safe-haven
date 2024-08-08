from typing import Any


class FQDN:
    def __init__(self, fqdn: Any, *nothing: list[Any], **kwags: dict[Any, Any]) -> None: ...
    @property
    def is_valid(self) -> bool: ...
