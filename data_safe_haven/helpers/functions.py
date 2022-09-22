# Standard library imports
import hashlib
import secrets
import string


def alphanumeric(input: str) -> str:
    return "".join(filter(lambda x: x in (string.ascii_letters + string.digits), input))


def hash(input: str) -> str:
    return hashlib.sha512(str.encode(input)).hexdigest()


def hex_string(length: int) -> str:
    """Generate a string of 'length' random hexadecimal characters."""
    return secrets.token_hex(length)


def password(length: int) -> str:
    """Generate a string of 'length' random alphanumeric characters. Require at least one lower-case, one upper-case and one digit."""
    alphabet = string.ascii_letters + string.digits
    while True:
        password = "".join(secrets.choice(alphabet) for _ in range(length))
        if (
            any(c.islower() for c in password)
            and any(c.isupper() for c in password)
            and any(c.isdigit() for c in password)
        ):
            break
    return password


def random_letters(length: int) -> str:
    """Generate a string of 'length' random letters."""
    return "".join(secrets.choice(string.ascii_letters) for _ in range(length))
