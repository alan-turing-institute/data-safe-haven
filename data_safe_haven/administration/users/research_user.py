# Standard library imports
import contextlib
import datetime
from typing import Any

# Local imports
from data_safe_haven.helpers import (
    hex_string,
)


class ResearchUser:
    def __init__(
        self,
        account_status=None,
        email_address=None,
        first_name=None,
        is_researcher=False,
        last_name=None,
        phone_number=None,
        uid_number=None,
        username=None,
        password_hash=None,
        password_salt=None,
        password_date=None,
    ):
        self.account_status = account_status
        self.email_address = email_address
        self.first_name = first_name
        self.is_researcher = is_researcher
        self.last_name = last_name
        self.phone_number = phone_number
        self.uid_number = int(uid_number) if uid_number else None
        self.username_ = username
        self.password_hash = password_hash if password_hash else hex_string(64)
        self.password_salt = password_salt if password_hash else hex_string(64)
        self.password_date = (
            password_date
            if password_date
            else datetime.datetime.utcnow().replace(tzinfo=datetime.timezone.utc)
        )

    @classmethod
    def from_csv(cls, **kwargs):
        return cls(**kwargs)

    @property
    def username(self):
        if self.username_:
            return self.username_
        return f"{self.first_name}.{self.last_name}".lower()

    def __eq__(self, other: Any):
        if isinstance(other, ResearchUser):
            return self.username == other.username
        return False

    def __str__(self):
        return f"{self.first_name} {self.last_name} '{self.username}' (UID: {self.uid_number}). Email {self.email_address}, phone {self.phone_number}, status '{self.account_status}'"
