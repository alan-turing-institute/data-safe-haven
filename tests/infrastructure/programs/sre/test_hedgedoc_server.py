import pytest

from data_safe_haven.infrastructure.programs.sre.hedgedoc_server import (
    SREHedgeDocServerProps,
)


class TestSREHedgeDocServer:
    def test_log_level_conversion_error(self) -> None:
        log_level = SREHedgeDocServerProps.log_level_convert("error")
        assert log_level == "error"

    def test_log_level_conversion_warn(self) -> None:
        log_level = SREHedgeDocServerProps.log_level_convert("warn")
        assert log_level == "warn"

    def test_log_level_conversion_info(self) -> None:
        log_level = SREHedgeDocServerProps.log_level_convert("info")
        assert log_level == "info"

    def test_log_level_conversion_debug(self) -> None:
        log_level = SREHedgeDocServerProps.log_level_convert("debug")
        assert log_level == "debug"

    def test_log_level_conversion_trace(self) -> None:
        log_level = SREHedgeDocServerProps.log_level_convert("trace")
        assert log_level == "debug"

    def test_log_level_conversion_invalid(self) -> None:
        with pytest.raises(
            ValueError,
            match=r"Logging level must be one of error, warn, info, debug or trace.",
        ):
            SREHedgeDocServerProps.log_level_convert("invalid")

        with pytest.raises(
            ValueError,
            match=r"Logging level must be one of error, warn, info, debug or trace.",
        ):
            SREHedgeDocServerProps.log_level_convert(0)
