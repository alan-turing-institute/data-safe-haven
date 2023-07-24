# Standard library imports
import base64
import hashlib
import secrets
import string
from typing import List, Sequence


def alphanumeric(input_string: str) -> str:
    """Strip any characters that are not letters or numbers from a string."""
    return "".join(
        filter(lambda x: x in (string.ascii_letters + string.digits), input_string)
    )


def b64decode(input_string: str) -> str:
    return base64.b64decode(input_string.encode("utf-8")).decode()


def b64encode(input_string: str) -> str:
    return base64.b64encode(input_string.encode("utf-8")).decode()


def hex_string(length: int) -> str:
    """Generate a string of 'length' random hexadecimal characters."""
    return secrets.token_hex(length)


def password(length: int) -> str:
    """Generate a string of 'length' random alphanumeric characters. Require at least one lower-case, one upper-case and one digit."""
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


def sha256hash(input_string: str) -> str:
    """Return the SHA256 hash of a string as a string."""
    return hashlib.sha256(str.encode(input_string, encoding="utf-8")).hexdigest()


def truncate_tokens(tokens: Sequence[str], max_length: int) -> List[str]:
    output_tokens = list(tokens)
    token_lengths = [len(t) for t in output_tokens]
    while sum(token_lengths) > max_length:
        for idx in range(len(output_tokens)):
            if len(output_tokens[idx]) == max(token_lengths):
                output_tokens[idx] = output_tokens[idx][:-1]
                token_lengths[idx] -= 1
                break
    return output_tokens
