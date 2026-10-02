import pytest

from data_safe_haven.infrastructure.programs.sre.identity import (
    SREIdentityProps,
)


class TestSREIdentity:
    def test_log_level_conversion_error(self) -> None:
        log_level = SREIdentityProps.log_level_convert("error")
        assert log_level == ""

    def test_log_level_conversion_warn(self) -> None:
        log_level = SREIdentityProps.log_level_convert("warn")
        assert log_level == ""

    def test_log_level_conversion_info(self) -> None:
        log_level = SREIdentityProps.log_level_convert("info")
        assert log_level == ""

    def test_log_level_conversion_debug(self) -> None:
        log_level = SREIdentityProps.log_level_convert("debug")
        assert log_level == "true"

    def test_log_level_conversion_trace(self) -> None:
        log_level = SREIdentityProps.log_level_convert("trace")
        assert log_level == "true"

    def test_log_level_conversion_invalid(self) -> None:
        with pytest.raises(
            ValueError,
            match=r"Logging level must be one of error, warn, info, debug or trace.",
        ):
            SREIdentityProps.log_level_convert("invalid")

        with pytest.raises(
            ValueError,
            match=r"Logging level must be one of error, warn, info, debug or trace.",
        ):
            SREIdentityProps.log_level_convert(0)
