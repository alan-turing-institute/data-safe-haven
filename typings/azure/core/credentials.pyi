from typing_extensions import Protocol

class TokenCredential(Protocol):
    pass

class AzureSasCredential:
    def __init__(self, signature: str) -> None: ...

class AzureNamedKeyCredential:
    def __init__(self, name: str, key: str) -> None: ...
