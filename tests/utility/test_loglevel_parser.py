import pytest

from data_safe_haven.utility import LogLevelParser

validator: dict[str, list[str]] = {
    "default": ["error", "warn", "info", "trace", "debug"],
    "gitea": ["not debug", "debug"],
    "nexus": ["trace"],
    "dns": ["log=warn", "log=debug"],
    "any": [],
}


class TestLogLevelParser:
    @pytest.mark.parametrize(
        "log_levels,validator",
        [
            ['info;gitea="not debug";nexus=trace;any="a b c"', validator],
            ['info;gitea="not debug";nexus=trace;dns="log=warn"', validator],
            ['default=info;gitea="debug";dns="log=debug";any=*', validator],
            ['debug"', validator],
            ["default=info;;;;", validator],
            ["", validator],
            ['any=""', validator],
        ],
    )
    def test_valid(self, log_levels: str, validator: dict[str, list[str]]) -> None:
        assert LogLevelParser.validate_logging_levels(log_levels, validator)

    @pytest.mark.parametrize(
        "log_levels,validator",
        [
            ['info;gitea="not warn";nexus=trace;dns="log=warn";any=";;;"', validator],
            ['default=info;gitea="debug";dns="debug"', validator],
            ["gitea====info", validator],
            ['""', validator],
            ['default=""', validator],
            ["default=", validator],
            ["default", validator],
        ],
    )
    def test_invalid(self, log_levels: str, validator: dict[str, list[str]]) -> None:
        assert not LogLevelParser.validate_logging_levels(log_levels, validator)

    @pytest.mark.parametrize(
        "log_levels,service,result",
        [
            ['info;gitea="not debug";nexus=trace;any="a b c"', "gitea", "not debug"],
            ['info;gitea="not debug";nexus=trace;dns="log=warn"', "nexus", "trace"],
            ['default=info;gitea="debug";dns="log=debug",any=*', "hedgedoc", "INFO"],
            ['debug"', "default", "DEBUG"],
            ["", "default", "DEBUG"],
        ],
    )
    def test_service_log_level_upper(
        self, log_levels: str, service: str, result: str
    ) -> None:
        def upper(log_level: str) -> str:
            return log_level.upper()

        assert (
            LogLevelParser.service_logging_level(log_levels, service, upper) == result
        )

    @pytest.mark.parametrize(
        "log_levels,service,result",
        [
            ['info;gitea="not debug";nexus=trace;any="a b c"', "gitea", "not debug"],
            ['info;gitea="not debug";nexus=trace;dns="log=warn"', "nexus", "trace"],
            ['default=info;gitea="debug";dns="log=debug",any=*', "hedgedoc", "info"],
            ['debug"', "default", "debug"],
            ["", "default", "debug"],
        ],
    )
    def test_service_log_level_identity(
        self, log_levels: str, service: str, result: str
    ) -> None:
        assert LogLevelParser.service_logging_level(log_levels, service, None) == result
