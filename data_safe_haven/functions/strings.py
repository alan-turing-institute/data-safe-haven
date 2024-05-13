import base64
import datetime
import hashlib
import random
import secrets
import string
import uuid
from collections.abc import Sequence

import pytz

from data_safe_haven.exceptions import DataSafeHavenInputError


def alphanumeric(input_string: str) -> str:
    """Strip any characters that are not letters or numbers from a string."""
    return "".join(filter(str.isalnum, input_string))


def sanitise_sre_name(name: str) -> str:
    return alphanumeric(name).lower()


def b64encode(input_string: str) -> str:
    """Encode a normal string into a Base64 string."""
    return base64.b64encode(input_string.encode("utf-8")).decode()


def next_occurrence(hour: int, minute: int, timezone: str) -> str:
    """
    Get an ISO-formatted string representing the next occurence in UTC of a daily
    repeating time in the local timezone.
    """
    try:
        local_tz = pytz.timezone(timezone)
        local_dt = datetime.datetime.now(local_tz).replace(
            hour=hour,
            minute=minute,
            second=0,
            microsecond=0,
        ) + datetime.timedelta(days=1)
        utc_dt = local_dt.astimezone(pytz.utc)
        return utc_dt.isoformat()
    except pytz.exceptions.UnknownTimeZoneError as exc:
        msg = f"Timezone '{timezone}' was not recognised.\n{exc}"
        raise DataSafeHavenInputError(msg) from exc
    except ValueError as exc:
        msg = f"Time '{hour}:{minute}' was not recognised.\n{exc}"
        raise DataSafeHavenInputError(msg) from exc


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
    """Return a string using underscores as a separator"""
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
