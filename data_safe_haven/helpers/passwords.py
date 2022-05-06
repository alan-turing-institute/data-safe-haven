# Standard library imports
import secrets
import string


def password(length):
    """Generate an alphanumeric password of a given length."""
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def hex_string(length):
    """Generate a hexadecimal string of a given length."""
    return secrets.token_hex(length)
