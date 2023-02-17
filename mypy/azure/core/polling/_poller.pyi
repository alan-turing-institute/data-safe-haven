from typing import Any, Callable, Generic, Optional, TypeVar

PollingReturnType = TypeVar("PollingReturnType")

class PollingMethod(Generic[PollingReturnType]):
    pass

class LROPoller(Generic[PollingReturnType]):
    def __init__(
        self,
        client: Any,
        initial_response: Any,
        deserialization_callback: Callable,
        polling_method: PollingMethod,
    ) -> None: ...
    def result(self, timeout: Optional[float] = ...) -> PollingReturnType: ...
    def done(self) -> bool: ...
