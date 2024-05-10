import datetime

import pytz


def time_as_string(hour: int, minute: int, timezone: str) -> str:
    """Get the next occurence of a repeating daily time as a string"""
    dt = datetime.datetime.now(datetime.UTC).replace(
        hour=hour,
        minute=minute,
        second=0,
        microsecond=0,
        tzinfo=pytz.timezone(timezone),
    ) + datetime.timedelta(days=1)
    return dt.isoformat()
