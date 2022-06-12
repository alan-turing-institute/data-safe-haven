# Standard library imports
import csv
from typing import Sequence

# Local imports
from data_safe_haven.exceptions import DataSafeHavenUserHandlingException
from data_safe_haven.mixins import AzureMixin, LoggingMixin
from .azuread_users import AzureADUsers
from .research_user import ResearchUser
from .guacamole_users import GuacamoleUsers


class UserHandler(LoggingMixin, AzureMixin):
    def __init__(
        self,
        config,
        aad_application_id,
        aad_application_secret,
        postgresql_password,
        *args,
        **kwargs,
    ):
        super().__init__(
            subscription_name=config.azure.subscription_name, *args, **kwargs
        )
        self.cfg = config
        self.azuread = AzureADUsers(
            config.azure.aad_tenant_id,
            aad_application_id,
            aad_application_secret,
            config.azure.aad_group_research_users,
        )
        self.guacamole = GuacamoleUsers(config, postgresql_password)

    def add(self, users_csv_path: str) -> None:
        """Add AzureAD and Guacamole users

        Raises:
            DataSafeHavenUserHandlingException if the users could not be added
        """
        try:
            # Construct user list
            with open(users_csv_path) as f_csv:
                new_users = [
                    ResearchUser.from_csv(
                        account_enabled=True,
                        domain_suffix=self.cfg.azure.domain_suffix,
                        **user,
                    )
                    for user in csv.DictReader(f_csv, delimiter=";")
                ]
            for new_user in new_users:
                self.debug(f"Processing new user: {new_user}")

            # Commit changes
            self.azuread.add(new_users)
            self.guacamole.add(new_users)
        except Exception as exc:
            raise DataSafeHavenUserHandlingException(
                f"Could not add users from '{users_csv_path}'.\n{str(exc)}"
            )

    def list(self) -> None:
        """List AzureAD and Guacamole users

        Raises:
            DataSafeHavenUserHandlingException if the users could not be listed
        """
        try:
            user_data = []
            azuread_usernames = [user.preferred_username for user in self.azuread.users]
            guacamole_usernames = [user.preferred_username for user in self.guacamole.users]
            for username in sorted(set(azuread_usernames + guacamole_usernames)):
                user_data.append(
                    [
                        username,
                        "x" if username in azuread_usernames else "",
                        "x" if username in guacamole_usernames else "",
                    ]
                )
            user_headers = ["username", "In AzureAD", "In Guacamole"]
            for line in self.tabulate(user_headers, user_data):
                self.info(line)
        except Exception as exc:
            raise DataSafeHavenUserHandlingException(
                f"Could not list users.\n{str(exc)}"
            )


    def remove(self, user_names: Sequence[str]) -> None:
        """Remove AzureAD and Guacamole users

        Raises:
            DataSafeHavenUserHandlingException if the users could not be removed
        """
        try:
            # Construct user lists
            azuread_users_to_remove = [
                user for user in self.azuread.users if user.username in user_names
            ]
            guacamole_users_to_remove = [
                user for user in self.guacamole.users if user.username in user_names
            ]

            # Commit changes
            self.azuread.remove(azuread_users_to_remove)
            self.guacamole.remove(guacamole_users_to_remove)
        except Exception as exc:
            raise DataSafeHavenUserHandlingException(
                f"Could not remove users: {user_names}.\n{str(exc)}"
            )

    def set(self, users_csv_path: str) -> None:
        """Set AzureAD and Guacamole users

        Raises:
            DataSafeHavenUserHandlingException if the users could not be set to the desired list
        """
        try:
            # Construct user lists
            with open(users_csv_path) as f_csv:
                new_users = [
                    ResearchUser.from_csv(
                        account_enabled=True,
                        domain_suffix=self.cfg.azure.domain_suffix,
                        **user,
                    )
                    for user in csv.DictReader(f_csv, delimiter=";")
                ]
            for new_user in new_users:
                self.debug(f"Processing user: {new_user}")

            # Keep existing users with the same username
            azuread_users = [user for user in self.azuread.users if user in new_users]
            guacamole_users = [user for user in self.guacamole.users if user in new_users]

            # Add any new users
            azuread_users += [user for user in new_users if user not in azuread_users]
            guacamole_users += [user for user in new_users if user not in guacamole_users]

            # Commit changes
            self.azuread.set(azuread_users)
            self.guacamole.set(guacamole_users)
        except Exception as exc:
            raise DataSafeHavenUserHandlingException(
                f"Could not set users from '{users_csv_path}'.\n{str(exc)}"
            )
