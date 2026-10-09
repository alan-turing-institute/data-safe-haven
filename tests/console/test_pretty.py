import pytest
from pytest import CaptureFixture, MonkeyPatch
from rich.console import Console

from data_safe_haven.console import pretty
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

    @pytest.mark.parametrize("soft_wrap", [False, True])
    def test_pretty_print_soft_wrap(
        self,
        soft_wrap: bool,  # noqa: FBT001
        capsys: CaptureFixture[str],
        monkeypatch: MonkeyPatch,
    ) -> None:
        # Fix the width, as Rich otherwise reads it from the environment
        monkeypatch.setattr(pretty, "console", Console(width=80))
        long_url = "https://example.com/" + "a" * 500
        pretty_print(long_url, soft_wrap=soft_wrap)

        lines = capsys.readouterr().out.splitlines()
        assert "".join(lines) == long_url
        if soft_wrap:
            assert len(lines) == 1
        else:
            assert all(len(line) <= 80 for line in lines)
