import pytest

from data_safe_haven.logging.plain_file_handler import PlainFileHandler


class TestPlainFileHandler:
    def test_strip_rich_formatting(self):
        assert PlainFileHandler.strip_rich_formatting("[green]Hello[/]") == "Hello"

    @pytest.mark.parametrize("escape", ["\033", "\x1B", "\u001b", "\x1B"])
    def test_strip_ansi_escapes(self, escape):
        assert (
            PlainFileHandler.strip_ansi_escapes(f"{escape}[31;1;4mHello{escape}[0m")
            == "Hello"
        )
