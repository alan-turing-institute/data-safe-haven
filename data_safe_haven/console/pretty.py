from typing import Any

from rich.console import Console, JustifyMethod, OverflowMethod
from rich.style import Style

console = Console()


def pretty_print(
    *objects: Any,
    sep: str = " ",
    end: str = "\n",
    style: str | Style | None = None,
    justify: JustifyMethod | None = None,
    overflow: OverflowMethod | None = None,
    no_wrap: bool | None = None,
    emoji: bool | None = None,
    markup: bool | None = None,
    highlight: bool | None = None,
    width: int | None = None,
    height: int | None = None,
    crop: bool = True,
    soft_wrap: bool | None = None,
    new_line_start: bool = False,
) -> None:
    console.print(
        *objects,
        sep,
        end,
        style,
        justify,
        overflow,
        no_wrap,
        emoji,
        markup,
        highlight,
        width,
        height,
        crop,
        soft_wrap,
        new_line_start,
    )
