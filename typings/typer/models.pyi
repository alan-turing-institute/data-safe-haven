from typing import Any, Callable, TypeVar

CommandFunctionType = TypeVar("CommandFunctionType", bound=Callable[..., Any])
DefaultType = TypeVar("DefaultType")

def Default(value: DefaultType) -> DefaultType: ...
