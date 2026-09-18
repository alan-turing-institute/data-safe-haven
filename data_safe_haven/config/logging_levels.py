"""SRE configuration file backed by blob storage"""

from collections import OrderedDict

from pulumi_azure_native import monitor

# Map level names to enum values
LOGGING_LEVELS = OrderedDict(
    {
        "error": [
            monitor.KnownSyslogDataSourceLogLevels.ERROR,
            monitor.KnownSyslogDataSourceLogLevels.CRITICAL,
            monitor.KnownSyslogDataSourceLogLevels.ALERT,
            monitor.KnownSyslogDataSourceLogLevels.EMERGENCY,
        ],
        "warn": [
            monitor.KnownSyslogDataSourceLogLevels.NOTICE,
            monitor.KnownSyslogDataSourceLogLevels.WARNING,
        ],
        "info": [
            monitor.KnownSyslogDataSourceLogLevels.INFO,
        ],
        "debug": [
            monitor.KnownSyslogDataSourceLogLevels.DEBUG,
        ],
        "trace": [],
    }
)
