"""Parse environment variables"""

import re


class LogLevelParser:
    """Parse environment variables"""

    @staticmethod
    def parse_logging_levels(log_levels: str) -> dict[str, str]:
        """Parse a string that has the following format:
        1. A list of key value pairs in the format key=value
        2. Each key=value pair is separated by a colon
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
                        re.findall(r'".+?"|[^=][^=]*', item)
                        for item in
                        # Split at colons, respecting quotes
                        re.findall(r'".+?"|[^;][^;]*', log_levels)
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
        2. Each key=value pair is separated by a colon
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
