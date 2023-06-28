# Standard library imports
import csv
from typing import Any, Dict, List, Sequence

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.exceptions import DataSafeHavenUserHandlingException
from data_safe_haven.external.api import GraphApi
from data_safe_haven.mixins import AzureMixin, LoggingMixin
from .active_directory_users import ActiveDirectoryUsers
from .azure_ad_users import AzureADUsers
from .guacamole_users import GuacamoleUsers
from .research_user import ResearchUser


class UserHandler(LoggingMixin, AzureMixin):
    def __init__(
        self,
        config: Config,
        graph_api: GraphApi,
        *args: Any,
        **kwargs: Any,
    ):
        super().__init__(subscription_name=config.subscription_name, *args, **kwargs)
        self.active_directory_users = ActiveDirectoryUsers(config)
        self.azure_ad_users = AzureADUsers(graph_api)
        self.sre_guacamole_users = {
            sre_name: GuacamoleUsers(config, sre_name) for sre_name in config.sre.keys()
        }

    def add(self, users_csv_path: str) -> None:
        """Add AzureAD and Guacamole users

        Raises:
            DataSafeHavenUserHandlingException if the users could not be added
        """
        try:
            # Construct user list
            with open(users_csv_path, encoding="utf-8") as f_csv:
                reader = csv.DictReader(f_csv)
                for required_field in ["GivenName", "Surname", "Phone", "Email"]:
                    if (not reader.fieldnames) or (
                        required_field not in reader.fieldnames
                    ):
                        raise ValueError(
                            f"Missing required CSV field '{required_field}'."
                        )
                users = [
                    ResearchUser(
                        country="GB",
                        email_address=user["Email"],
                        given_name=user["GivenName"],
                        phone_number=user["Phone"],
                        surname=user["Surname"],
                    )
                    for user in reader
                ]
            for user in users:
                self.debug(f"Processing new user: {user}")

            # Commit changes
            self.active_directory_users.add(users)
        except Exception as exc:
            raise DataSafeHavenUserHandlingException(
                f"Could not add users from '{users_csv_path}'.\n{str(exc)}"
            ) from exc

    def get_usernames(self) -> Dict[str, List[str]]:
        """Load usernames from all sources"""
        usernames = {}
        usernames["Azure AD"] = self.get_usernames_azure_ad()
        usernames["Domain controller"] = self.get_usernames_domain_controller()
        for sre_name in self.sre_guacamole_users.keys():
            usernames[f"SRE {sre_name}"] = self.get_usernames_guacamole(sre_name)
        return usernames

    def get_usernames_azure_ad(self) -> List[str]:
        """Load usernames from Azure AD"""
        return [user.username for user in self.azure_ad_users.list()]

    def get_usernames_domain_controller(self) -> List[str]:
        """Load usernames from all domain controller"""
        return [user.username for user in self.active_directory_users.list()]

    def get_usernames_guacamole(self, sre_name: str) -> List[str]:
        """Load usernames from Guacamole"""
        return [user.username for user in self.sre_guacamole_users[sre_name].list()]

    def list(self) -> None:
        """List Active Directory, AzureAD and Guacamole users

        Raises:
            DataSafeHavenUserHandlingException if the users could not be listed
        """
        try:
            # Load usernames
            usernames = self.get_usernames()
            # Fill user information as a table
            user_headers = ["username"] + list(usernames.keys())
            user_data = []
            for username in sorted(set(sum(usernames.values(), []))):
                user_memberships = [username]
                for category in user_headers[1:]:
                    user_memberships.append(
                        "x" if username in usernames[category] else ""
                    )
                user_data.append(user_memberships)

            # Write user information as a table
            for line in self.tabulate(user_headers, user_data):
                self.info(line)
        except Exception as exc:
            raise DataSafeHavenUserHandlingException(
                f"Could not list users.\n{str(exc)}"
            ) from exc

    def register(self, sre_name: str, user_names: Sequence[str]) -> None:
        """Register usernames with Guacamole database

        Raises:
            DataSafeHavenUserHandlingException if the users could not be registered in the Guacamole database
        """
        try:
            # Register users in correct security group
            self.active_directory_users.register(sre_name, user_names)
            # Retrieve list of users
            users = self.active_directory_users.list(sre_name)
            # Add specified users to Guacamole
            self.sre_guacamole_users[sre_name].add(users)
        except Exception as exc:
            raise DataSafeHavenUserHandlingException(
                f"Could not register {len(user_names)} users with SRE '{sre_name}'.\n{str(exc)}"
            ) from exc

    def remove(self, user_names: Sequence[str]) -> None:
        """Remove AzureAD and Guacamole users

        Raises:
            DataSafeHavenUserHandlingException if the users could not be removed
        """
        try:
            # Construct user lists
            active_directory_users_to_remove = [
                user
                for user in self.active_directory_users.list()
                if user.username in user_names
            ]

            # Commit changes
            self.active_directory_users.remove(active_directory_users_to_remove)
        except Exception as exc:
            raise DataSafeHavenUserHandlingException(
                f"Could not remove users: {user_names}.\n{str(exc)}"
            ) from exc

    def set(self, users_csv_path: str) -> None:
        """Set AzureAD and Guacamole users

        Raises:
            DataSafeHavenUserHandlingException if the users could not be set to the desired list
        """
        try:
            # Construct user list
            with open(users_csv_path, encoding="utf-8") as f_csv:
                reader = csv.DictReader(f_csv)
                for required_field in ["GivenName", "Surname", "Phone", "Email"]:
                    if (not reader.fieldnames) or (
                        required_field not in reader.fieldnames
                    ):
                        raise ValueError(
                            f"Missing required CSV field '{required_field}'."
                        )
                desired_users = [
                    ResearchUser(
                        country="GB",
                        email_address=user["Email"],
                        given_name=user["GivenName"],
                        phone_number=user["Phone"],
                        surname=user["Surname"],
                    )
                    for user in reader
                ]
            for user in desired_users:
                self.debug(f"Processing user: {user}")

            # Keep existing users with the same username
            active_directory_desired_users = [
                user
                for user in self.active_directory_users.list()
                if user.username in [u.username for u in desired_users]
            ]

            # Construct list of new users
            active_directory_desired_users = [
                user
                for user in desired_users
                if user not in active_directory_desired_users
            ]

            # Commit changes
            self.active_directory_users.set(active_directory_desired_users)
        except Exception as exc:
            raise DataSafeHavenUserHandlingException(
                f"Could not set users from '{users_csv_path}'.\n{str(exc)}"
            ) from exc
