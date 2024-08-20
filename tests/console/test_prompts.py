import io
import sys

import pytest

from data_safe_haven.console.prompts import confirm


class TestConfirm:
    @pytest.mark.parametrize(
        "default_to_yes,default_to_yes_string,response,expected_result",
        [
            (True, "y", "y", True),
            (True, "y", "n", False),
            (True, "y", "\n", True),
            (False, "n", "y", True),
            (False, "n", "n", False),
            (False, "n", "\n", False),
        ],
    )
    def test_confirm(
        self,
        default_to_yes,
        default_to_yes_string,
        response,
        expected_result,
        capsys,
        mocker,
    ):
        mocker.patch.object(sys, "stdin", io.StringIO(response))

        result = confirm("yes or no?", default_to_yes=default_to_yes)
        assert result is expected_result

        captured = capsys.readouterr()
        assert f"yes or no? [y/n] ({default_to_yes_string}):" in captured.out
