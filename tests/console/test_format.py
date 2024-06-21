from data_safe_haven.console.format import tabulate


class TestTabulate:
    def test_tabulate(self, capsys):
        header = ["head1", "head2"]
        rows = [["11", "12"], ["21", "22"]]
        tabulate(header=header, rows=rows)
        captured = capsys.readouterr()
        for line in [
            "┏━━━━━━━┳━━━━━━━┓",
            "┃ head1 ┃ head2 ┃",
            "┡━━━━━━━╇━━━━━━━┩",
            "│ 11    │ 12    │",
            "│ 21    │ 22    │",
            "└───────┴───────┘",
        ]:
            assert line in captured.out

    def test_tabulate_no_header(self, capsys):
        rows = [["11", "12"], ["21", "22"]]
        tabulate(rows=rows)
        captured = capsys.readouterr()
        for line in [
            "┏━━━━┳━━━━┓",
            "┃    ┃    ┃",
            "┡━━━━╇━━━━┩",
            "│ 11 │ 12 │",
            "│ 21 │ 22 │",
            "└────┴────┘",
        ]:
            assert line in captured.out

    def test_tabulate_no_rows(self, capsys):
        header = ["head1", "head2"]
        tabulate(header=header)
        captured = capsys.readouterr()
        for line in [
            "┏━━━━━━━┳━━━━━━━┓",
            "┃ head1 ┃ head2 ┃",
            "┡━━━━━━━╇━━━━━━━┩",
            "└───────┴───────┘",
        ]:
            assert line in captured.out
