import pytest

from data_safe_haven.infrastructure.programs.sre.identity import (
    SREIdentityProps,
)


class TestSREIdentity:
    @pytest.mark.parametrize(
        "log_level,result",
        [
            ["error", ""],
            ["warn", ""],
            ["info", ""],
            ["debug", "true"],
            ["trace", "true"],
        ],
    )
    def test_log_level_conversion_error(self, log_level: str, result: str) -> None:
        log_level = SREIdentityProps.log_level_convert(log_level)
        assert log_level == result

    @pytest.mark.parametrize("log_level", ["invalid", "0"])
    def test_log_level_conversion_invalid(self, log_level: str) -> None:
        with pytest.raises(
            ValueError,
            match=r"Logging level must be one of error, warn, info, debug, trace.",
        ):
            SREIdentityProps.log_level_convert(log_level)
