"""Definition of a Singleton metaclass"""
from typing import Any, ClassVar, Generic, TypeVar, cast

T = TypeVar("T")


class Singleton(type, Generic[T]):
    _instances: ClassVar[dict] = {}

    def __call__(cls, *args: Any, **kwargs: Any) -> T:
        if cls not in cls._instances:
            cls._instances[cls] = super().__call__(*args, **kwargs)
        return cast(T, cls._instances[cls])
