# Standard library imports
import csv
from typing import Sequence

# Local imports
from data_safe_haven.mixins import AzureMixin, LoggingMixin
from .research_user import ResearchUser
from .guacamole_users import GuacamoleUsers
from .ldap_users import LdapUsers


class UserHandler(LoggingMixin, AzureMixin):
    def __init__(self, config, postgresql_password, *args, **kwargs):
        super().__init__(
            subscription_name=config.azure.subscription_name, *args, **kwargs
        )
        self.cfg = config
        self.ldap = LdapUsers(config)
        self.guacamole = GuacamoleUsers(config, postgresql_password)

    def add(self, users_csv: str) -> None:
        # Construct user list
        with open(users_csv) as f_csv:
            new_users = [
                ResearchUser.from_csv(account_status="enabled", **user)
                for user in csv.DictReader(f_csv, delimiter=";")
            ]
        for new_user in new_users:
            self.debug(f"Processing new user: {new_user}")

        # Commit changes
        self.ldap.add(new_users)
        self.guacamole.add(new_users)

    def list(self) -> None:
        """List LDAP and Guacamole users"""
        user_data = []
        ldap_usernames = [user.username for user in self.ldap.users]
        guacamole_usernames = [user.username for user in self.guacamole.users]
        for username in sorted(set(ldap_usernames + guacamole_usernames)):
            user_data.append(
                [
                    username,
                    "x" if username in ldap_usernames else "",
                    "x" if username in guacamole_usernames else "",
                ]
            )
        user_headers = ["username", "In LDAP", "In Guacamole"]
        for line in self.tabulate(user_headers, user_data):
            self.info(line)

    def remove(self, user_names: Sequence[str]) -> None:
        """Remove LDAP and Guacamole users"""
        # Construct user lists
        ldap_users_to_remove = [
            user for user in self.ldap.users if user.username in user_names
        ]
        guacamole_users_to_remove = [
            user for user in self.guacamole.users if user.username in user_names
        ]

        # Commit changes
        self.ldap.remove(ldap_users_to_remove)
        self.guacamole.remove(guacamole_users_to_remove)

    def set(self, users_csv: str) -> None:
        # Construct user lists
        with open(users_csv) as f_csv:
            new_users = [
                ResearchUser.from_csv(account_status="enabled", **user)
                for user in csv.DictReader(f_csv, delimiter=";")
            ]
        for new_user in new_users:
            self.debug(f"Processing user: {new_user}")

        # Keep existing users with the same username
        ldap_users = [user for user in self.ldap.users if user in new_users]
        guacamole_users = [user for user in self.guacamole.users if user in new_users]

        # Add any new users
        ldap_users += [user for user in new_users if user not in ldap_users]
        guacamole_users += [user for user in new_users if user not in guacamole_users]

        # Commit changes
        self.ldap.set(ldap_users)
        self.guacamole.set(guacamole_users)
