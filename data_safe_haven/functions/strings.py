import base64
import hashlib
import random
import secrets
import string
import uuid
from collections.abc import Sequence

import bcrypt


def alphanumeric(input_string: str) -> str:
    """Strip any characters that are not letters or numbers from a string."""
    return "".join(
        filter(lambda x: x in (string.ascii_letters + string.digits), input_string)
    )


def b64decode(input_string: str) -> str:
    """Decode a Base64 string into a normal string."""
    return base64.b64decode(input_string.encode("utf-8")).decode()


def b64encode(input_string: str) -> str:
    """Encode a normal string into a Base64 string."""
    return base64.b64encode(input_string.encode("utf-8")).decode()


def bcrypt_encode(input_string: str, salt: str) -> str:
    """
    Use bcrypt to encrypt an input string.
    See https://en.wikipedia.org/wiki/Bcrypt#Description for structure.
    """
    encrypted_bytes = bcrypt.hashpw(input_string.encode(), salt.encode())
    return encrypted_bytes.decode(encoding="utf-8")


def bcrypt_salt() -> str:
    """Generate a bcrypt salt as a string.

    Returns:
      $algorithm$cost$salt: str
    """
    return bcrypt.gensalt().decode()


def hex_string(length: int) -> str:
    """Generate a string of 'length' random hexadecimal characters."""
    return secrets.token_hex(length)


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


def random_letters(length: int) -> str:
    """Generate a string of 'length' random letters."""
    return "".join(secrets.choice(string.ascii_letters) for _ in range(length))


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
    generator = random.Random()
    generator.seed(seed)
    return uuid.UUID(int=generator.getrandbits(128), version=4)


def sha256hash(input_string: str) -> str:
    """Return the SHA256 hash of a string as a string."""
    return hashlib.sha256(str.encode(input_string, encoding="utf-8")).hexdigest()


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
