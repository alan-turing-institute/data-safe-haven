from typing import IO, Generic, Iterator, Optional, TypeVar
from _typeshed import Incomplete

T = TypeVar("T", bytes, str)

class StorageStreamDownloader(Generic[T]):
    name: Incomplete
    container: Incomplete
    properties: Incomplete
    size: Incomplete
    def __init__(
        self,
        clients: Incomplete | None = ...,
        config: Incomplete | None = ...,
        start_range: Incomplete | None = ...,
        end_range: Incomplete | None = ...,
        validate_content: Incomplete | None = ...,
        encryption_options: Incomplete | None = ...,
        max_concurrency: int = ...,
        name: Incomplete | None = ...,
        container: Incomplete | None = ...,
        encoding: Incomplete | None = ...,
        download_cls: Incomplete | None = ...,
        **kwargs
    ) -> None: ...
    def __len__(self) -> int: ...
    def chunks(self) -> Iterator[bytes]: ...
    def read(self, size: Optional[int] = ...) -> T: ...
    def readall(self) -> T: ...
    def content_as_bytes(self, max_concurrency: int = ...): ...
    def content_as_text(self, max_concurrency: int = ..., encoding: str = ...): ...
    def readinto(self, stream: IO[T]) -> int: ...
    def download_to_stream(self, stream, max_concurrency: int = ...): ...
