import re
import unicodedata
from typing import Any

# Some letters are not decomposed by Unicode NFKD normalization.
MAX_ENTRA_NICKNAME_LENGTH = 64

_NAME_TRANSLITERATION = str.maketrans(
    {"ł": "l", "ø": "o", "đ": "d", "ð": "d", "þ": "th", "æ": "ae", "œ": "oe"}
)


def _username_part(value: str | None) -> str:
    """Create an ASCII-only, Entra-safe component of a generated username."""
    if not value or not value.strip():
        msg = "Both given name and surname are required to generate a username."
        raise ValueError(msg)
    normalized = unicodedata.normalize(
        "NFKD", value.strip().casefold().translate(_NAME_TRANSLITERATION)
    )
    ascii_name = "".join(char for char in normalized if not unicodedata.combining(char))
    ascii_name = ascii_name.encode("ascii", errors="ignore").decode("ascii")
    # Preserve double surnames using hyphens; apostrophes do not act as separators.
    ascii_name = re.sub(r"[\s_\-]+", "-", ascii_name.replace("'", ""))
    ascii_name = re.sub(r"[^a-z0-9-]", "", ascii_name).strip("-")
    if not ascii_name:
        msg = "Name cannot be transliterated into an ASCII Entra username."
        raise ValueError(msg)
    return ascii_name


class ResearchUser:
    def __init__(
        self,
        account_enabled: bool | None = None,  # noqa: FBT001
        country: str | None = None,
        domain: str | None = None,
        email_address: str | None = None,
        given_name: str | None = None,
        phone_number: str | None = None,
        sam_account_name: str | None = None,
        surname: str | None = None,
        user_principal_name: str | None = None,
    ) -> None:
        self.account_enabled = account_enabled
        self.country = country
        self.domain = domain
        self.email_address = email_address
        self.given_name = given_name
        self.phone_number = phone_number
        self.sam_account_name = sam_account_name
        self.surname = surname
        self.user_principal_name = user_principal_name

    def __hash__(self) -> int:
        return hash(
            (
                self.account_enabled,
                self.country,
                self.domain,
                self.email_address,
                self.given_name,
                self.phone_number,
                self.sam_account_name,
                self.surname,
                self.user_principal_name,
            )
        )

    @property
    def display_name(self) -> str:
        return f"{self.given_name} {self.surname}"

    @property
    def preferred_username(self) -> str:
        if self.user_principal_name:
            return self.user_principal_name
        return self.username

    @property
    def username(self) -> str:
        if self.sam_account_name:
            return self.sam_account_name
        username = f"{_username_part(self.given_name)}.{_username_part(self.surname)}"
        if len(username) > MAX_ENTRA_NICKNAME_LENGTH:
            msg = (
                "Generated username exceeds the 64-character Entra mailNickname limit."
            )
            raise ValueError(msg)
        return username

    def __eq__(self, other: Any) -> bool:
        if isinstance(other, ResearchUser):
            return any(
                [
                    self.username == other.username,
                    self.preferred_username == other.preferred_username,
                ]
            )
        return False

    def __str__(self) -> str:
        return f"{self.display_name} '{self.username}'."
