import csv
import pathlib
from collections.abc import Sequence

from data_safe_haven.config import Config
from data_safe_haven.exceptions import DataSafeHavenUserHandlingError
from data_safe_haven.external import GraphApi
from data_safe_haven.utility import LoggingSingleton

from .active_directory_users import ActiveDirectoryUsers
from .azure_ad_users import AzureADUsers
from .guacamole_users import GuacamoleUsers
from .research_user import ResearchUser


class UserHandler:
    def __init__(
        self,
        config: Config,
        graph_api: GraphApi,
    ):
        self.active_directory_users = ActiveDirectoryUsers(config)
        self.azure_ad_users = AzureADUsers(graph_api)
        self.config = config
        self.logger = LoggingSingleton()
        self.sre_guacamole_users_: dict[str, GuacamoleUsers] = {}

    def add(self, users_csv_path: pathlib.Path) -> None:
        """Add AzureAD and Guacamole users

        Raises:
            DataSafeHavenUserHandlingError if the users could not be added
        """
        try:
            # Construct user list
            with open(users_csv_path, encoding="utf-8") as f_csv:
                dialect = csv.Sniffer().sniff(f_csv.read(), delimiters=";,")
                f_csv.seek(0)
                reader = csv.DictReader(f_csv, dialect=dialect)
                for required_field in [
                    "GivenName",
                    "Surname",
                    "Phone",
                    "Email",
                    "CountryCode",
                ]:
                    if (not reader.fieldnames) or (
                        required_field not in reader.fieldnames
                    ):
                        msg = f"Missing required CSV field '{required_field}'."
                        raise ValueError(msg)
                users = [
                    ResearchUser(
                        account_enabled=True,
                        country=user["CountryCode"],
                        email_address=user["Email"],
                        given_name=user["GivenName"],
                        phone_number=user["Phone"],
                        surname=user["Surname"],
                    )
                    for user in reader
                ]
            for user in users:
                self.logger.debug(f"Processing new user: {user}")

            # Add users to AzureAD
            self.azure_ad_users.add(users)
        except Exception as exc:
            msg = f"Could not add users from '{users_csv_path}'.\n{exc}"
            raise DataSafeHavenUserHandlingError(msg) from exc

    def get_usernames(self) -> dict[str, list[str]]:
        """Load usernames from all sources"""
        usernames = {}
        usernames["Azure AD"] = self.get_usernames_azure_ad()
        for sre_name in self.config.sre_names:
            usernames[f"SRE {sre_name}"] = self.get_usernames_guacamole(sre_name)
        return usernames

    def get_usernames_azure_ad(self) -> list[str]:
        """Load usernames from Azure AD"""
        return [user.username for user in self.azure_ad_users.list()]

    def get_usernames_domain_controller(self) -> list[str]:
        """Load usernames from all domain controller"""
        return [user.username for user in self.active_directory_users.list()]

    def get_usernames_guacamole(self, sre_name: str) -> list[str]:
        """Lazy-load usernames from Guacamole"""
        try:
            if sre_name not in self.sre_guacamole_users_.keys():
                self.sre_guacamole_users_[sre_name] = GuacamoleUsers(
                    self.config, sre_name
                )
            return [
                user.username for user in self.sre_guacamole_users_[sre_name].list()
            ]
        except Exception:
            self.logger.error(f"Could not load users for SRE '{sre_name}'.")
            return []

    def list(self) -> None:
        """List Active Directory, AzureAD and Guacamole users

        Raises:
            DataSafeHavenUserHandlingError if the users could not be listed
        """
        try:
            # Load usernames
            usernames = self.get_usernames()
            # Fill user information as a table
            user_headers = ["username", *list(usernames.keys())]
            user_data = []
            for username in sorted(
                {name for names in usernames.values() for name in names}
            ):
                user_memberships = [username]
                for category in user_headers[1:]:
                    user_memberships.append(
                        "x" if username in usernames[category] else ""
                    )
                user_data.append(user_memberships)

            # Write user information as a table
            for line in self.logger.tabulate(user_headers, user_data):
                self.logger.info(line)
        except Exception as exc:
            msg = f"Could not list users.\n{exc}"
            raise DataSafeHavenUserHandlingError(msg) from exc

    def register(self, sre_name: str, user_names: Sequence[str]) -> None:
        """Register usernames with SRE

        Raises:
            DataSafeHavenUserHandlingError if the users could not be registered in the SRE
        """
        try:
            # Add users to the SRE security group
            self.azure_ad_users.register(sre_name, user_names)
        except Exception as exc:
            msg = f"Could not register {len(user_names)} users with SRE '{sre_name}'.\n{exc}"
            raise DataSafeHavenUserHandlingError(msg) from exc

    def remove(self, user_names: Sequence[str]) -> None:
        """Remove AzureAD and Guacamole users

        Raises:
            DataSafeHavenUserHandlingError if the users could not be removed
        """
        try:
            # Construct user lists
            self.logger.info(f"Attempting to remove {len(user_names)} user(s).")
            azuread_users_to_remove = [
                user
                for user in self.azure_ad_users.list()
                if user.username in user_names
            ]

            # Commit changes
            self.logger.info(
                f"Found {len(azuread_users_to_remove)} valid user(s) to remove."
            )
            self.azure_ad_users.remove(azuread_users_to_remove)
        except Exception as exc:
            msg = f"Could not remove users: {user_names}.\n{exc}"
            raise DataSafeHavenUserHandlingError(msg) from exc

    def set(self, users_csv_path: str) -> None:
        """Set AzureAD and Guacamole users

        Raises:
            DataSafeHavenUserHandlingError if the users could not be set to the desired list
        """
        try:
            # Construct user list
            with open(users_csv_path, encoding="utf-8") as f_csv:
                reader = csv.DictReader(f_csv)
                for required_field in ["GivenName", "Surname", "Phone", "Email"]:
                    if (not reader.fieldnames) or (
                        required_field not in reader.fieldnames
                    ):
                        msg = f"Missing required CSV field '{required_field}'."
                        raise ValueError(msg)
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
                self.logger.debug(f"Processing user: {user}")

            # Keep existing users with the same username
            azuread_desired_users = [
                user
                for user in self.azure_ad_users.list()
                if user.username in [u.username for u in desired_users]
            ]

            # Construct list of new users
            azuread_desired_users = [
                user for user in desired_users if user not in azuread_desired_users
            ]

            # Commit changes
            self.azure_ad_users.set(azuread_desired_users)
        except Exception as exc:
            msg = f"Could not set users from '{users_csv_path}'.\n{exc}"
            raise DataSafeHavenUserHandlingError(msg) from exc

    def unregister(self, sre_name: str, user_names: Sequence[str]) -> None:
        """Unregister usernames with SRE

        Raises:
            DataSafeHavenUserHandlingError if the users could not be registered in the SRE
        """
        try:
            # Remove users from the SRE security group
            self.azure_ad_users.unregister(sre_name, user_names)
        except Exception as exc:
            msg = f"Could not unregister {len(user_names)} users with SRE '{sre_name}'.\n{exc}"
            raise DataSafeHavenUserHandlingError(msg) from exc
