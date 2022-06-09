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
        account_enabled=None,
        azure_oid=None,
        display_name=None,
        email_address=None,
        first_name=None,
        homedir=None,
        is_global_admin=False,
        is_researcher=False,
        last_name=None,
        phone_number=None,
        uid_number=None,
        username=None,
        user_principal_name=None,
        password_hash=None,
        password_salt=None,
        password_date=None,
        shell=None,
    ):
        self.account_enabled = account_enabled
        self.azure_oid = azure_oid
        self.display_name_ = display_name
        self.email_address = email_address
        self.first_name = first_name
        self.homedir = homedir
        self.is_global_admin = is_global_admin
        self.is_researcher = is_researcher
        self.last_name = last_name
        self.phone_number = phone_number
        self.uid_number = int(uid_number) if uid_number else None
        self.username_ = username
        self.user_principal_name = user_principal_name
        self.password_hash = password_hash if password_hash else hex_string(64)
        self.password_salt = password_salt if password_hash else hex_string(64)
        self.password_date = (
            password_date
            if password_date
            else datetime.datetime.utcnow().replace(tzinfo=datetime.timezone.utc)
        )
        self.shell = shell

    @classmethod
    def from_graph_api(cls, **kwargs):
        return cls(
            account_enabled=kwargs.get("accountEnabled", None),
            azure_oid=kwargs.get("id", None),
            display_name=kwargs.get("displayName", None),
            email_address=kwargs.get("mail", None),
            first_name=kwargs.get("givenName", None),
            homedir=kwargs.get("homedir", None),
            is_global_admin=kwargs.get("isGlobalAdmin"),
            is_researcher=True,
            last_name=kwargs.get("surname", None),
            phone_number=kwargs.get("telephoneNumber", None),
            uid_number=kwargs.get("uid", None),
            username=kwargs.get("user", None),
            user_principal_name=kwargs.get("userPrincipalName", None),
            password_hash=None,
            password_salt=None,
            password_date=None,
            shell=kwargs.get("shell", None),
        )

    @classmethod
    def from_csv(cls, domain_suffix, **kwargs):
        user_principal_name = (
            f"{kwargs['first_name']}.{kwargs['last_name']}@{domain_suffix}".lower()
        )
        return cls(
            user_principal_name=user_principal_name, is_researcher=True, **kwargs
        )

    @property
    def display_name(self):
        if self.display_name_:
            return self.display_name_
        return f"{self.first_name} {self.last_name}"

    @property
    def username(self):
        if self.username_:
            return self.username_
        return f"{self.first_name}.{self.last_name}".lower()

    @property
    def preferred_username(self):
        return self.user_principal_name

    def __eq__(self, other: Any):
        if isinstance(other, ResearchUser):
            return any(
                [
                    self.username == other.username,
                    self.preferred_username == other.preferred_username,
                ]
            )
        return False

    def __str__(self):
        return f"{self.first_name} {self.last_name} '{self.username}' (UID: {self.uid_number})."
