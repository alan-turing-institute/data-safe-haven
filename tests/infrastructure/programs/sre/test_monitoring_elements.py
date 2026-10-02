import pytest
from pulumi_azure_native import monitor

from data_safe_haven.infrastructure.programs.sre.monitoring_elements import (
    SREMonitoringElementsProps,
)

log_levels = [
    monitor.KnownSyslogDataSourceLogLevels.EMERGENCY,
    monitor.KnownSyslogDataSourceLogLevels.ALERT,
    monitor.KnownSyslogDataSourceLogLevels.CRITICAL,
    monitor.KnownSyslogDataSourceLogLevels.ERROR,
    monitor.KnownSyslogDataSourceLogLevels.WARNING,
    monitor.KnownSyslogDataSourceLogLevels.NOTICE,
    monitor.KnownSyslogDataSourceLogLevels.INFO,
    monitor.KnownSyslogDataSourceLogLevels.DEBUG,
]

log_level_testdata = [
    pytest.param(log_levels[:4], "error", id="error"),
    pytest.param(log_levels[:5], "warn", id="warn"),
    pytest.param(log_levels[:7], "info", id="info"),
    pytest.param(log_levels[:8], "debug", id="debug"),
    pytest.param(log_levels[:8], "trace", id="trace"),
]


class TestMonitoringElements:
    @pytest.mark.parametrize("syslog_levels,loglevel", log_level_testdata)
    def test_log_level_conversion(self, syslog_levels, loglevel) -> None:
        log_levels = SREMonitoringElementsProps.log_level_convert(loglevel)

        # Should contain
        for level in log_levels:
            assert level in syslog_levels

        # And nothing else
        assert len(log_levels) == len(syslog_levels)

    def test_log_level_conversion_invalid(self) -> None:
        with pytest.raises(
            ValueError,
            match=r"Logging level must be one of error, warn, info, debug or trace.",
        ):
            SREMonitoringElementsProps.log_level_convert("invalid")

        with pytest.raises(
            ValueError,
            match=r"Logging level must be one of error, warn, info, debug or trace.",
        ):
            SREMonitoringElementsProps.log_level_convert(0)
