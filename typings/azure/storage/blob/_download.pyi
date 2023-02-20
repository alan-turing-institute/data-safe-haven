from typing import Generic, TypeVar

from _typeshed import Incomplete

T = TypeVar("T", bytes, str)

class StorageStreamDownloader(Generic[T]):
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
