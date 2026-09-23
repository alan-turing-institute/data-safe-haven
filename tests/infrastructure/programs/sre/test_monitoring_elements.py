import pytest
from pulumi_azure_native import monitor

from data_safe_haven.infrastructure.programs.sre.monitoring_elements import (
    SREMonitoringElementsProps,
)


class TestMonitoringElements:
    def test_log_level_conversion_error(self) -> None:
        intended = [
            monitor.KnownSyslogDataSourceLogLevels.ERROR,
            monitor.KnownSyslogDataSourceLogLevels.CRITICAL,
            monitor.KnownSyslogDataSourceLogLevels.ALERT,
            monitor.KnownSyslogDataSourceLogLevels.EMERGENCY,
        ]
        log_levels = SREMonitoringElementsProps.log_level_convert("error")

        # Should contain
        for level in intended:
            assert level in log_levels

        # And nothing else
        assert len(log_levels) == len(intended)

    def test_log_level_conversion_warn(self) -> None:
        intended = [
            monitor.KnownSyslogDataSourceLogLevels.ERROR,
            monitor.KnownSyslogDataSourceLogLevels.CRITICAL,
            monitor.KnownSyslogDataSourceLogLevels.ALERT,
            monitor.KnownSyslogDataSourceLogLevels.EMERGENCY,
            monitor.KnownSyslogDataSourceLogLevels.NOTICE,
            monitor.KnownSyslogDataSourceLogLevels.WARNING,
        ]
        log_levels = SREMonitoringElementsProps.log_level_convert("warn")

        # Should contain
        for level in intended:
            assert level in log_levels

        # And nothing else
        assert len(log_levels) == len(intended)

    def test_log_level_conversion_info(self) -> None:
        intended = [
            monitor.KnownSyslogDataSourceLogLevels.ERROR,
            monitor.KnownSyslogDataSourceLogLevels.CRITICAL,
            monitor.KnownSyslogDataSourceLogLevels.ALERT,
            monitor.KnownSyslogDataSourceLogLevels.EMERGENCY,
            monitor.KnownSyslogDataSourceLogLevels.NOTICE,
            monitor.KnownSyslogDataSourceLogLevels.WARNING,
            monitor.KnownSyslogDataSourceLogLevels.INFO,
        ]
        log_levels = SREMonitoringElementsProps.log_level_convert("info")

        # Should contain
        for level in intended:
            assert level in log_levels

        # And nothing else
        assert len(log_levels) == len(intended)

    def test_log_level_conversion_debug(self) -> None:
        intended = [
            monitor.KnownSyslogDataSourceLogLevels.ERROR,
            monitor.KnownSyslogDataSourceLogLevels.CRITICAL,
            monitor.KnownSyslogDataSourceLogLevels.ALERT,
            monitor.KnownSyslogDataSourceLogLevels.EMERGENCY,
            monitor.KnownSyslogDataSourceLogLevels.NOTICE,
            monitor.KnownSyslogDataSourceLogLevels.WARNING,
            monitor.KnownSyslogDataSourceLogLevels.INFO,
            monitor.KnownSyslogDataSourceLogLevels.DEBUG,
        ]
        log_levels = SREMonitoringElementsProps.log_level_convert("debug")

        # Should contain
        for level in intended:
            assert level in log_levels

        # And nothing else
        assert len(log_levels) == len(intended)

    def test_log_level_conversion_trace(self) -> None:
        intended = [
            monitor.KnownSyslogDataSourceLogLevels.ERROR,
            monitor.KnownSyslogDataSourceLogLevels.CRITICAL,
            monitor.KnownSyslogDataSourceLogLevels.ALERT,
            monitor.KnownSyslogDataSourceLogLevels.EMERGENCY,
            monitor.KnownSyslogDataSourceLogLevels.NOTICE,
            monitor.KnownSyslogDataSourceLogLevels.WARNING,
            monitor.KnownSyslogDataSourceLogLevels.INFO,
            monitor.KnownSyslogDataSourceLogLevels.DEBUG,
        ]
        log_levels = SREMonitoringElementsProps.log_level_convert("trace")

        # Should contain
        for level in intended:
            assert level in log_levels

        # And nothing else
        assert len(log_levels) == len(intended)

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
