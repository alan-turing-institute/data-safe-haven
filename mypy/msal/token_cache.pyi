from typing import Optional

class TokenCache(object):
    def __init__(self) -> None: ...

class SerializableTokenCache(TokenCache):
    def deserialize(self, state: Optional[str]) -> None: ...
