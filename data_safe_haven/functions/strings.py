import base64
import datetime
import hashlib
import random
import secrets
import string
import uuid
from collections.abc import Sequence

import pytz

from data_safe_haven.exceptions import DataSafeHavenValueError


def alphanumeric(input_string: str) -> str:
    """Strip any characters that are not letters or numbers from a string."""
    return "".join(filter(str.isalnum, input_string))


def b64encode(input_string: str) -> str:
    """Encode a normal string into a Base64 string."""
    return base64.b64encode(input_string.encode("utf-8")).decode()


def get_key_vault_name(stack_name: str) -> str:
    """Key Vault names have a maximum of 24 characters"""
    return f"{''.join(truncate_tokens(stack_name.split('-'), 17))}secrets"


def get_sre_storage_account_name(
    stack_name: str,
    purpose: str,
    legacy_prefix_length: int,
    component_name: str | None = None,
) -> str:
    """Build a storage account name that identifies the full SRE stack.

    Azure storage account names are globally unique and limited to 24 ASCII
    lowercase alphanumeric characters. The legacy convention trimmed the
    stack name to a short prefix and, in some cases, appended a hash of a
    constant component name, so different SREs could collide (issue #2370).

    Untruncated names retain their legacy value to avoid needless replacement.
    When a stack would be truncated, reserve eight hex digits for a hash of
    the *entire* stack rather than repeating its truncated prefix.

    WARNING: Existing long-name SREs will receive new storage account names.
    Those deployments require a reviewed data migration before an upgrade.
    """
    stack_prefix = "".join(stack_name.split("-"))
    legacy_prefix = "".join(
        truncate_tokens(stack_name.split("-"), legacy_prefix_length)
    )
    legacy_suffix = sha256hash(component_name) if component_name else ""
    legacy_name = alphanumeric(f"{legacy_prefix}{purpose}{legacy_suffix}")[:24]
    if legacy_prefix == stack_prefix:
        return legacy_name

    digest_length = 8
    prefix_length = 24 - len(purpose) - digest_length
    if prefix_length < 0:
        raise ValueError("Storage account purpose is too long for hashing.")
    readable_prefix = alphanumeric(stack_name)[:prefix_length]
    return f"{readable_prefix}{purpose}{sha256hash(stack_name)[:digest_length]}".lower()


def get_desired_state_storage_account_name(stack_name: str, component_name: str) -> str:
    """Get the collision-resistant name for the SRE desired-state storage."""
    return get_sre_storage_account_name(stack_name, "desiredstate", 11, component_name)


def next_occurrence(
    hour: int, minute: int, timezone: str, *, time_format: str = "iso"
) -> str:
    """
    Get an ISO-formatted string representing the next occurence in UTC of a daily
    repeating time in the local timezone.

    Args:
        hour: hour in the local timezone
        minute: minute in the local timezone
        timezone: string representation of the local timezone
        time_format: either 'iso' (YYYY-MM-DDTHH:MM:SS.mmmmmm) or 'iso_minute' (YYYY-MM-DD HH:MM)
    """
    try:
        local_tz = pytz.timezone(timezone)
        local_dt = datetime.datetime.now(local_tz).replace(
            hour=hour,
            minute=minute,
            second=0,
            microsecond=0,
        )
        utc_dt = local_dt.astimezone(pytz.utc)
        # Add one day until this datetime is at least 1 hour in the future.
        # This ensures that any Azure functions which depend on this datetime being in
        # the future should treat it as valid.
        utc_near_future = datetime.datetime.now(pytz.utc) + datetime.timedelta(hours=1)
        while utc_dt < utc_near_future:
            utc_dt += datetime.timedelta(days=1)
        if time_format == "iso":
            return utc_dt.isoformat()
        elif time_format == "iso_minute":
            return utc_dt.strftime(r"%Y-%m-%d %H:%M")
        else:
            msg = f"Time format '{time_format}' was not recognised."
            raise DataSafeHavenValueError(msg)
    except pytz.exceptions.UnknownTimeZoneError as exc:
        msg = f"Timezone '{timezone}' was not recognised."
        raise DataSafeHavenValueError(msg) from exc
    except ValueError as exc:
        msg = f"Time '{hour}:{minute}' was not recognised."
        raise DataSafeHavenValueError(msg) from exc


def password(length: int) -> str:
    """
    Generate a string of 'length' random alphanumeric characters.
    Require at least one lower-case, one upper-case and one digit.
    """
    alphabet = string.ascii_letters + string.digits
    while True:
        password_ = "".join(secrets.choice(alphabet) for _ in range(length))
        if (
            any(c.islower() for c in password_)
            and any(c.isupper() for c in password_)
            and any(c.isdigit() for c in password_)
        ):
            break
    return password_


def replace_separators(input_string: str, separator: str = "") -> str:
    """Return a string replacing all instances of [ _-.] with the desired separator."""
    return (
        input_string.replace(" ", separator)
        .replace("_", separator)
        .replace("-", separator)
        .replace(".", separator)
    )


def seeded_uuid(seed: str) -> uuid.UUID:
    """Return a UUID seeded from a given string."""
    generator = random.Random()  # noqa: S311
    generator.seed(seed)
    return uuid.UUID(int=generator.getrandbits(128), version=4)


def sha256hash(input_string: str) -> str:
    """Return the SHA256 hash of a string as a string."""
    return hashlib.sha256(input_string.encode("utf-8")).hexdigest()


def truncate_tokens(tokens: Sequence[str], max_length: int) -> list[str]:
    """
    Recursively remove the final character from the longest strings in the input.
    Terminate when the total length of all strings is no greater than max_length.
    For example:
        truncate_tokens(["the", "quick", "fox"], 6) -> ["th", "qu", "fo"]
    """
    output_tokens = list(tokens)
    token_lengths = [len(t) for t in output_tokens]
    while sum(token_lengths) > max_length:
        for idx in range(len(output_tokens)):
            if len(output_tokens[idx]) == max(token_lengths):
                output_tokens[idx] = output_tokens[idx][:-1]
                token_lengths[idx] -= 1
                break
    return output_tokens
