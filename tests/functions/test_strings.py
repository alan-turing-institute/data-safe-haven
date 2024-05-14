import datetime

import pytest
import pytz

from data_safe_haven.exceptions import DataSafeHavenInputError
from data_safe_haven.functions import next_occurrence, sanitise_sre_name


def test_next_occurrence_is_within_next_day():
    next_time = next_occurrence(5, 13, "Australia/Perth")
    dt_next_time = datetime.datetime.fromisoformat(next_time)
    dt_utc_now = datetime.datetime.now(datetime.UTC)
    assert dt_next_time > dt_utc_now
    assert dt_next_time < dt_utc_now + datetime.timedelta(days=1)


def test_next_occurrence_has_correct_time():
    next_time = next_occurrence(5, 13, "Australia/Perth")
    dt_as_utc = datetime.datetime.fromisoformat(next_time)
    dt_as_local = dt_as_utc.astimezone(pytz.timezone("Australia/Perth"))
    assert dt_as_local.hour == 5
    assert dt_as_local.minute == 13


def test_next_occurrence_invalid_hour():
    with pytest.raises(DataSafeHavenInputError) as exc_info:
        next_occurrence(99, 13, "Europe/London")
    assert exc_info.match(r"Time '99:13' was not recognised.")


def test_next_occurrence_invalid_minute():
    with pytest.raises(DataSafeHavenInputError) as exc_info:
        next_occurrence(5, 99, "Europe/London")
    assert exc_info.match(r"Time '5:99' was not recognised.")


def test_next_occurrence_invalid_timezone():
    with pytest.raises(DataSafeHavenInputError) as exc_info:
        next_occurrence(5, 13, "Mars/OlympusMons")
    assert exc_info.match(r"Timezone 'Mars/OlympusMons' was not recognised.")


@pytest.mark.parametrize(
    "value,expected",
    [("Test SRE", "testsre"), ("%*aBc", "abc"), ("MY_SRE", "mysre")],
)
def test_sanitise_sre_name(value, expected):
    assert sanitise_sre_name(value) == expected
