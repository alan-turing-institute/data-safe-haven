import pytest

from data_safe_haven.utility import LogLevelParser

validator = {
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
            ['default=info;gitea="debug";dns="log=debug",any=*', validator],
            ['debug"', validator],
            ["default=info;;;;", validator],
            ["", validator],
            ['any=""', validator],
        ],
    )
    def test_valid(self, log_levels, validator):
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
    def test_invalid(self, log_levels, validator):
        assert not LogLevelParser.validate_logging_levels(log_levels, validator)
