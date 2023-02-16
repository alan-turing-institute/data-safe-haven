from typing import Any, Optional

from clikit.api.args.format import Argument, Option

def argument(
    name: str,
    description: Optional[str] = ...,
    optional: bool = ...,
    multiple: bool = ...,
    default: Optional[Any] = ...,
) -> Argument: ...
def option(
    long_name: str,
    short_name: Optional[str] = ...,
    description: Optional[str] = ...,
    flag: bool = ...,
    value_required: bool = ...,
    multiple: bool = ...,
    default: Optional[Any] = ...,
) -> Option: ...
