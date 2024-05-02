import pytest

from data_safe_haven.functions import sanitise_sre_name


@pytest.mark.parametrize(
    "value,expected",
    [("Test SRE", "testsre"), ("%*aBc", "abc"), ("MY_SRE", "mysre")],
)
def test_sanitise_sre_name(value, expected):
    assert sanitise_sre_name(value) == expected
