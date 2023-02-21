from typing import Any, Optional
import msrest.serialization
from _typeshed import Incomplete

class ContainerExecRequest(msrest.serialization.Model):
    def __init__(
        self,
        *,
        command: Optional[str] = ...,
        terminal_size: Optional["ContainerExecRequestTerminalSize"] = ...,
        **kwargs: Any
    ) -> None: ...

class ContainerExecRequestTerminalSize(msrest.serialization.Model):
    def __init__(
        self, *, rows: Optional[int] = ..., cols: Optional[int] = ..., **kwargs: Any
    ) -> None: ...

class ContainerExecResponse(msrest.serialization.Model):
    web_socket_uri: str
    password: str
    def __init__(
        self,
        *,
        web_socket_uri: Optional[str] = None,
        password: Optional[str] = None,
        **kwargs: Any
    ) -> None: ...

class ContainerGroup(Resource):
    ip_address: IpAddress
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...

class IpAddress(msrest.serialization.Model):
    ports: Incomplete
    type: str
    ip: str
    dns_name_label: str
    dns_name_label_reuse_policy: Incomplete
    fqdn: str
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...

class Resource(msrest.serialization.Model):
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
