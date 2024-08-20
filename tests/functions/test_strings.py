import pytest
from freezegun import freeze_time

from data_safe_haven.exceptions import DataSafeHavenValueError
from data_safe_haven.functions import (
    get_key_vault_name,
    json_safe,
    next_occurrence,
)


class TestNextOccurrence:
    @pytest.mark.parametrize(
        "hour,minute,timezone,expected",
        [
            (5, 13, "Australia/Perth", "2024-01-02T21:13:00+00:00"),
            (0, 13, "Australia/Perth", "2024-01-02T16:13:00+00:00"),
            (20, 13, "Australia/Perth", "2024-01-02T12:13:00+00:00"),
            (20, 13, "Europe/London", "2024-01-02T20:13:00+00:00"),
        ],
    )
    @freeze_time("1am on Jan 2nd, 2024")
    def test_next_occurrence(self, hour, minute, timezone, expected):
        next_time = next_occurrence(hour, minute, timezone)
        assert next_time == expected

    @freeze_time("1am on July 2nd, 2024")
    def test_dst(self):
        next_time = next_occurrence(13, 5, "Europe/London")
        assert next_time == "2024-07-02T12:05:00+00:00"

    @freeze_time("1am on Jan 2nd, 2024")
    def test_timeformat(self):
        next_time = next_occurrence(5, 13, "Australia/Perth", time_format="iso_minute")
        assert next_time == "2024-01-02 21:13"

    @freeze_time("9pm on Jan 2nd, 2024")
    def test_is_tomorrow(self):
        next_time = next_occurrence(5, 13, "Australia/Perth")
        assert next_time == "2024-01-03T21:13:00+00:00"

    def test_invalid_hour(self):
        with pytest.raises(DataSafeHavenValueError) as exc_info:
            next_occurrence(99, 13, "Europe/London")
        assert exc_info.match(r"Time '99:13' was not recognised.")

    def test_invalid_minute(self):
        with pytest.raises(DataSafeHavenValueError) as exc_info:
            next_occurrence(5, 99, "Europe/London")
        assert exc_info.match(r"Time '5:99' was not recognised.")

    def test_invalid_timezone(self):
        with pytest.raises(DataSafeHavenValueError) as exc_info:
            next_occurrence(5, 13, "Mars/OlympusMons")
        assert exc_info.match(r"Timezone 'Mars/OlympusMons' was not recognised.")

    def test_invalid_timeformat(self):
        with pytest.raises(DataSafeHavenValueError) as exc_info:
            next_occurrence(5, 13, "Australia/Perth", time_format="invalid")
        assert exc_info.match(r"Time format 'invalid' was not recognised.")


@pytest.mark.parametrize(
    "value,expected",
    [
        (r"shm-a-sre-b", "shmasrebsecrets"),
        (r"shm-verylongshmname-sre-verylongsrename", "shmverylsreverylosecrets"),
        (r"a-long-string-with-lots-of-tokens", "alostrwitlotoftoksecrets"),
    ],
)
def test_get_key_vault_name(value, expected):
    assert get_key_vault_name(value) == expected


@pytest.mark.parametrize(
    "value,expected",
    [(r"Test SRE", "testsre"), (r"%*aBc", "abc"), (r"MY_SRE", "mysre")],
)
def test_json_safe(value, expected):
    assert json_safe(value) == expected
