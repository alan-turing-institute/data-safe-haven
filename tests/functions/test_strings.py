import datetime

import pytest
from freezegun import freeze_time

from data_safe_haven.exceptions import DataSafeHavenInputError
from data_safe_haven.functions import next_occurrence, sanitise_sre_name


@freeze_time(datetime.datetime(2024, 1, 2, 1, 0, tzinfo=datetime.UTC))
def test_next_occurrence():
    next_time = next_occurrence(5, 13, "Australia/Perth")
    assert next_time == "2024-01-02T21:13:00+00:00"


@freeze_time(datetime.datetime(2024, 1, 2, 1, 0, tzinfo=datetime.UTC))
def test_next_occurrence_timeformat():
    next_time = next_occurrence(5, 13, "Australia/Perth", time_format="iso_minute")
    assert next_time == "2024-01-02 21:13"


@freeze_time(datetime.datetime(2024, 1, 2, 23, 0, tzinfo=datetime.UTC))
def test_next_occurrence_is_tomorrow():
    next_time = next_occurrence(5, 13, "Australia/Perth")
    assert next_time == "2024-01-03T21:13:00+00:00"


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


def test_next_occurrence_invalid_timeformat():
    with pytest.raises(DataSafeHavenInputError) as exc_info:
        next_occurrence(5, 13, "Australia/Perth", time_format="invalid")
    assert exc_info.match(r"Time format 'invalid' was not recognised.")


@pytest.mark.parametrize(
    "value,expected",
    [("Test SRE", "testsre"), ("%*aBc", "abc"), ("MY_SRE", "mysre")],
)
def test_sanitise_sre_name(value, expected):
    assert sanitise_sre_name(value) == expected
