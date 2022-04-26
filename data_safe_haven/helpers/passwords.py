# Standard library imports
import secrets
import string

def password(length):
    """Generate an alphnumeric password."""
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))

def hex_string(length):
    return secrets.token_hex(length)
