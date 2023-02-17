from typing import Any

from .chained import ChainedTokenCredential

class DefaultAzureCredential(ChainedTokenCredential):
    def __init__(self, **kwargs: Any) -> None: ...
