"""Definition of a Singleton metaclass"""

from typing import Any, Generic, TypeVar

T = TypeVar("T")


class Singleton(type, Generic[T]):
    # It is not possible to wrap generics in ClassVar (https://github.com/python/mypy/issues/5144)
    _instances: dict["Singleton[T]", T] = {}  # noqa: RUF012

    def __call__(cls, *args: Any, **kwargs: Any) -> T:
        if cls not in cls._instances:
            cls._instances[cls] = super().__call__(*args, **kwargs)
        return cls._instances[cls]
