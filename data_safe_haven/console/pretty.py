from typing import Any

from rich.console import Console

console = Console()


def pretty_print(
    *objects: Any,
    sep: str = " ",
) -> None:
    console.print(
        *objects,
        sep=sep,
    )
