from data_safe_haven.logging.plain_file_handler import PlainFileHandler


class TestPlainFileHandler:
    def test_strip_formatting(self):
        assert PlainFileHandler.strip_formatting("[green]hello[/]") == "hello"
