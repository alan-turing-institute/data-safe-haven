from typing import Any
from azure.core.credentials import TokenCredential

class ChainedTokenCredential(TokenCredential):
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
