from rich.table import Table

from .pretty import pretty_print


def tabulate(
    header: list[str] | None = None, rows: list[list[str]] | None = None
) -> None:
    """Generate a table from header and rows

    Args:
        header: The table header
        rows: The table rows

    Returns:
        A list of strings representing the table
    """
    table = Table()
    if header:
        for item in header:
            table.add_column(item)
    if rows:
        for row in rows:
            table.add_row(*row)

    pretty_print(table)
