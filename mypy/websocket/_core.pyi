from typing import Any, Optional

from _typeshed import Incomplete

class WebSocket:
    def __init__(
        self,
        get_mask_key: Optional[Incomplete] = None,
        sockopt: Optional[Incomplete] = None,
        sslopt: Optional[Incomplete] = None,
        fire_cont_frame: Optional[bool] = False,
        enable_multithread: Optional[bool] = True,
        skip_utf8_validation: Optional[bool] = False,
        **_: Any
    ) -> None: ...
    def send(self, payload: str, opcode: Optional[int] = ...) -> int: ...
    def recv(self) -> str: ...
    def close(
        self,
        status: Optional[int] = ...,
        reason: Optional[bytes] = ...,
        timeout: Optional[int | float] = ...,
    ) -> None: ...

def create_connection(
    url: str,
    timeout: Optional[int | float] = None,
    class_: Optional[type[WebSocket]] = WebSocket,
    **options: Any
) -> WebSocket: ...
