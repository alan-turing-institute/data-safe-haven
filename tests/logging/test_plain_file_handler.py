from data_safe_haven.logging.plain_file_handler import PlainFileHandler


class TestPlainFileHandler:
    def test_strip_rich_formatting(self):
        assert PlainFileHandler.strip_rich_formatting("[green]Hello[/]") == "Hello"

    def test_strip_ansi_escapes(self):
        assert (
            PlainFileHandler.strip_ansi_escapes("\033[31;1;4mHello\033[0m") == "Hello"
        )
