"""Parse environment variables"""

import re
from collections.abc import Callable


class LogLevelParser:
    """Parse environment variables"""

    @staticmethod
    def parse_logging_levels(log_levels: str) -> dict[str, str]:
        """Parse a string that has the following format:
        1. A list of key value pairs in the format key=value
        2. Each key=value pair is separated by a semicolon
        3. Values surrounded by quotes are considered atomic
        4. Items without an equals are read as values and given the key "default"

        The result is parsed into a dictionary. For example, the following
        string:

        'info;gitea="not debug";nexus=trace;dns="log=warn"'

        Would be parsed into the following dictionary:

        {
            'default': 'info',
            'gitea'  : 'not debug',
            'nexus'  : 'trace',
            'dns'    : 'log=warn'
        }
        """
        parsed: dict[str, str] = {
            # Turn list into a dictionary
            item[0]: item[1]
            for item in [
                # Strip quotes surrounding key and value strings
                [value.strip('"') for value in item]
                for item in [
                    # Ensure default values have a key
                    ["default", *item] if len(item) == 1 else item
                    for item in [
                        # Split on equals keeping key=value pair sublists and respecting quotes
                        re.findall(r'[^="]*"[^"]*"|[^="]+', item)
                        for item in
                        # Split at semicolons, respecting quotes
                        re.findall(r'[^;"]*"[^"]*"|[^;"]+', log_levels)
                    ]
                ]
            ]
        }

        return parsed

    @staticmethod
    def validate_logging_levels(
        log_levels: str, validator: dict[str, list[str]]
    ) -> bool:
        """Validate a string has the following format:
        1. A list of key value pairs in the format key=value
        2. Each key=value pair is separated by a semicolon
        3. Values surrounded by quotes are considered atomic
        4. Items without an equals are read as values and given the key "default"

        validator should be a dictionary in the following format:
        {
            key: ["value", "value", ...],
            ...
        }

        Each key from the parsed string must have a key in the validator dictionary.

        For a key=value pair in the parsed list, the value must be contained
        in the list associated with the key in the validator.

        If the list associated with a validator key is empty, any value will be accepted.
        """
        valid = True
        try:
            parsed = LogLevelParser.parse_logging_levels(log_levels)
            for key, value in parsed.items():
                if key in validator:
                    acceptable = validator[key]
                    if acceptable != [] and value not in acceptable:
                        valid = False
                else:
                    valid = False
        except Exception:
            valid = False

        return valid

    @staticmethod
    def service_logging_level(
        log_levels: str, service: str, service_convert: Callable[[str], str] | None
    ) -> str:
        """Extract the logging level for a particular service.
        The process follows two steps.

        If a specific log level is specified for the service, use it directly.

        If no specific log level is specified for the service, fall back on the
        default log level, but pass it through the service's conversion function
        in order to choose the closest most appropriate value in the format
        required of the service.

        The logging level is extracted from the logging string using the
        parse_logging_levels() function.
        """
        mapping = LogLevelParser.parse_logging_levels(log_levels)
        log_level = ""

        if (service != "default") and (service in mapping):
            # This is a result for a specific service so apply no transformation
            log_level = mapping[service]
        else:
            # This is a default level so we must apply a transformation
            log_level = mapping.get("default", "debug")
            if service_convert is not None:
                log_level = service_convert(log_level)

        return log_level
