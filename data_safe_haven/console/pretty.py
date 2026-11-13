from typing import Any

from rich.console import Console

console = Console()


def pretty_print(
    *objects: Any,
    sep: str = " ",
    soft_wrap: bool = False,
) -> None:
    console.print(
        *objects,
        sep=sep,
        soft_wrap=soft_wrap,
    )
