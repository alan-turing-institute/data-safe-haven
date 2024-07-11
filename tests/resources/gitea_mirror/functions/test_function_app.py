# import azure.functions as func

from data_safe_haven.resources.gitea_mirror.functions.function_app import (
    str_or_none
)


class TestStrOrNone:
    def test_str_or_none(self):
        assert str_or_none("hello") == "hello"
        assert str_or_none(None) is None
