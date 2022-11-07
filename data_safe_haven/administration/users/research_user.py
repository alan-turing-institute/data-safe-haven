# Standard library imports
from typing import Any


class ResearchUser:
    def __init__(
        self,
        account_enabled: bool = None,
        email_address: str = None,
        given_name: str = None,
        phone_number: str = None,
        sam_account_name: str = None,
        surname: str = None,
        user_principal_name: str = None,
    ):
        self.account_enabled = account_enabled
        self.sam_account_name = sam_account_name
        self.given_name = given_name
        self.surname = surname
        self.phone_number = phone_number
        self.email_address = email_address
        self.user_principal_name = user_principal_name

    @property
    def username(self) -> str:
        if self.sam_account_name:
            return self.sam_account_name
        return f"{self.given_name}.{self.surname}".lower()

    @property
    def preferred_username(self) -> str:
        if self.user_principal_name:
            return self.user_principal_name
        return self.username

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
        return f"{self.given_name} {self.surname} '{self.username}'."
