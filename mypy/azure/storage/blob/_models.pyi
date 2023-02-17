from enum import Enum
from typing import Any

from azure.core import CaseInsensitiveEnumMeta

from ._shared.models import DictMixin

class BlobType(str, Enum, metaclass=CaseInsensitiveEnumMeta):
    BLOCKBLOB: str
    PAGEBLOB: str
    APPENDBLOB: str

class ContainerProperties(DictMixin):
    def __init__(self, **kwargs: Any) -> None: ...

class BlobProperties(DictMixin):
    def __init__(self, **kwargs: Any) -> None: ...
