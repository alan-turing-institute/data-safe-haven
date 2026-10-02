"""Logging levels configurable for use throughout the SRE"""

from collections import OrderedDict

from pulumi_azure_native import monitor

# Map level names to enum values
LOGGING_LEVELS = OrderedDict(
    {
        "error": [
            monitor.KnownSyslogDataSourceLogLevels.EMERGENCY,
            monitor.KnownSyslogDataSourceLogLevels.ALERT,
            monitor.KnownSyslogDataSourceLogLevels.CRITICAL,
            monitor.KnownSyslogDataSourceLogLevels.ERROR,
        ],
        "warn": [
            monitor.KnownSyslogDataSourceLogLevels.WARNING,
        ],
        "info": [
            monitor.KnownSyslogDataSourceLogLevels.NOTICE,
            monitor.KnownSyslogDataSourceLogLevels.INFO,
        ],
        "debug": [
            monitor.KnownSyslogDataSourceLogLevels.DEBUG,
        ],
        "trace": [],
    }
)
