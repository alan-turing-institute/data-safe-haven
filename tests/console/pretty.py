import pytest

from data_safe_haven.console.pretty import pretty_print


class TestPrettyPrint:
    @pytest.mark.parametrize(
        "objects,sep,expected,not_expected",
        [
            (["hello"], None, "hello", None),
            (["[green]hello[/]"], None, "hello", "[green]"),
            (["[bold red]hello[/]"], None, "hello", "[bold red]"),
            (["hello", "world"], None, "hello world", None),
            (["hello", "world"], "\n", "hello\nworld", None),
            ([(1, 2, 3)], "\n", "(1, 2, 3)", None),
            (["[link=https://example.com]abc[/]"], None, "abc", "example"),
        ],
    )
    def test_pretty_print(self, objects, sep, expected, not_expected, capsys):
        if sep is not None:
            pretty_print(*objects, sep=sep)
        else:
            pretty_print(*objects)

        captured = capsys.readouterr()
        assert expected in captured.out

        if not_expected is not None:
            assert not_expected not in captured.out
