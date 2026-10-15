import pytest
from freezegun import freeze_time

from data_safe_haven.exceptions import DataSafeHavenValueError
from data_safe_haven.functions import (
    alphanumeric,
    get_desired_state_storage_account_name,
    get_key_vault_name,
    get_sre_storage_account_name,
    next_occurrence,
    sha256hash,
    truncate_tokens,
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
    "stack",
    [
        "shm-pro-sre-dsg1234",
        "shm-pro-sre-dsg9876",
        "shm-cvdnetdev-sre-longname",
        "shm-cvdnetdev-sre-longname2",
        "shm-verylongshmname-sre-verylongsrename",
    ],
)
def test_desired_state_storage_name_is_valid_and_stable(stack):
    name = get_desired_state_storage_account_name(stack, "sre_desired_state")
    assert 3 <= len(name) <= 24
    assert name.isascii()
    assert name.islower()
    assert name.isalnum()
    assert name == get_desired_state_storage_account_name(stack, "sre_desired_state")


def test_desired_state_names_distinguish_sres_with_same_truncated_prefix():
    first = get_desired_state_storage_account_name(
        "shm-pro-sre-dsg1234", "sre_desired_state"
    )
    second = get_desired_state_storage_account_name(
        "shm-pro-sre-dsg9876", "sre_desired_state"
    )
    assert first != second
    assert first.startswith("shmpdesiredstate")
    assert second.startswith("shmpdesiredstate")


def test_desired_state_names_include_full_stack_hash_even_for_late_difference():
    names = {
        get_desired_state_storage_account_name(
            f"shm-production-sre-project-longname-{index:04d}",
            "sre_desired_state",
        )
        for index in range(100)
    }
    assert len(names) == 100


@pytest.mark.parametrize(
    "stack",
    ["shm-a", "sre-x", "shm-dev", "sre-research"],
)
def test_short_stacks_preserve_existing_storage_account_names(stack):
    expected = alphanumeric(
        f"{stack.replace('-', '')}desiredstate{sha256hash('sre_desired_state')}"
    )[:24]
    assert (
        get_desired_state_storage_account_name(stack, "sre_desired_state") == expected
    )


def test_storage_name_changes_only_when_truncation_loses_stack_suffix():
    short_name = get_desired_state_storage_account_name(
        "shm-a-sre-b", "sre_desired_state"
    )
    long_name = get_desired_state_storage_account_name(
        "shm-a-sre-b-verylong", "sre_desired_state"
    )
    assert short_name != long_name


@pytest.mark.parametrize(
    "purpose,budget,component",
    [
        ("desiredstate", 11, "sre_desired_state"),
        ("configdata", 14, None),
        ("sensitivedata", 11, "sre_data"),
        ("userdata", 16, "sre_data"),
    ],
)
def test_all_sre_storage_account_purposes_keep_unique_full_stack_suffix(
    purpose, budget, component
):
    first = get_sre_storage_account_name(
        "shm-pro-sre-verylong-dsg1234", purpose, budget, component
    )
    second = get_sre_storage_account_name(
        "shm-pro-sre-verylong-dsg9876", purpose, budget, component
    )
    assert first != second
    assert first.endswith(purpose + first[-8:])
    assert purpose in first
    assert purpose in second
    assert first.isascii() and first.isalnum() and first.islower()
    assert second.isascii() and second.isalnum() and second.islower()
    assert len(first) == len(second) == 24


@pytest.mark.parametrize(
    "purpose,budget,component",
    [
        ("desiredstate", 11, "sre_desired_state"),
        ("configdata", 14, None),
        ("sensitivedata", 11, "sre_data"),
        ("userdata", 16, "sre_data"),
    ],
)
def test_short_stacks_retain_legacy_names_for_all_storage_purposes(
    purpose, budget, component
):
    stack = "shm-a"
    component_hash = sha256hash(component) if component else ""
    expected = alphanumeric(f"shma{purpose}{component_hash}")[:24]
    assert get_sre_storage_account_name(stack, purpose, budget, component) == expected


def test_storage_purpose_length_must_allow_full_stack_hash():
    with pytest.raises(ValueError, match="too long"):
        get_sre_storage_account_name("shm-pro-sre-dsg1234", "purpose-way-too-long", 4)


def test_legacy_desired_state_name_collides_for_reported_sre_names():
    def legacy_name(stack):
        truncated = "".join(truncate_tokens(stack.split("-"), 11))
        return alphanumeric(
            f"{truncated}desiredstate{sha256hash('sre_desired_state')}"
        )[:24]

    first = legacy_name("shm-pro-sre-dsg1234")
    second = legacy_name("shm-pro-sre-dsg9876")
    assert first == second
    assert len(first) == 24
