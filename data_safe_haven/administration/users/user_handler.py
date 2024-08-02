import csv
import pathlib
from collections.abc import Sequence

from data_safe_haven import console
from data_safe_haven.config import Context, DSHPulumiConfig, SREConfig
from data_safe_haven.exceptions import DataSafeHavenUserHandlingError
from data_safe_haven.external import GraphApi
from data_safe_haven.logging import get_logger

from .entra_users import EntraUsers
from .guacamole_users import GuacamoleUsers
from .research_user import ResearchUser


class UserHandler:
    def __init__(
        self,
        context: Context,
        graph_api: GraphApi,
    ):
        self.entra_users = EntraUsers(graph_api)
        self.context = context
        self.logger = get_logger()

    def add(self, users_csv_path: pathlib.Path, domain: str) -> None:
        """Add users to Entra ID and Guacamole

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
                        domain=user.get("Domain", domain),
                        email_address=user["Email"],
                        given_name=user["GivenName"],
                        phone_number=user["Phone"],
                        surname=user["Surname"],
                    )
                    for user in reader
                ]
            for user in users:
                self.logger.debug(f"Processing new user: {user}")

            # Add users to Entra ID
            self.entra_users.add(users)
        except csv.Error as exc:
            msg = f"Could not add users from '{users_csv_path}'."
            raise DataSafeHavenUserHandlingError(msg) from exc

    def get_usernames(
        self, sre_name: str, pulumi_config: DSHPulumiConfig
    ) -> dict[str, list[str]]:
        """Load usernames from all sources"""
        usernames = {}
        usernames["Entra ID"] = self.get_usernames_entra_id()
        usernames[f"SRE {sre_name}"] = self.get_usernames_guacamole(
            sre_name,
            pulumi_config,
        )
        return usernames

    def get_usernames_entra_id(self) -> list[str]:
        """Load usernames from Entra ID"""
        return [user.username for user in self.entra_users.list()]

    def get_usernames_guacamole(
        self, sre_name: str, pulumi_config: DSHPulumiConfig
    ) -> list[str]:
        """Lazy-load usernames from Guacamole"""
        try:
            sre_config = SREConfig.from_remote_by_name(self.context, sre_name)
            guacamole_users = GuacamoleUsers(self.context, sre_config, pulumi_config)
            return [user.username for user in guacamole_users.list()]
        except Exception:
            self.logger.error(f"Could not load users for SRE '{sre_name}'.")
            return []

    def list(self, sre_name: str, pulumi_config: DSHPulumiConfig) -> None:
        """List Entra ID and Guacamole users

        Raises:
            DataSafeHavenUserHandlingError if the users could not be listed
        """
        try:
            # Load usernames
            usernames = self.get_usernames(sre_name, pulumi_config)
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

            console.tabulate(user_headers, user_data)
        except Exception as exc:
            msg = "Could not list users."
            raise DataSafeHavenUserHandlingError(msg) from exc

    def register(self, sre_name: str, user_names: Sequence[str]) -> None:
        """Register usernames with SRE

        Raises:
            DataSafeHavenUserHandlingError if the users could not be registered in the SRE
        """
        try:
            # Add users to the SRE security group
            self.entra_users.register(sre_name, user_names)
        except Exception as exc:
            msg = f"Could not register {len(user_names)} users with SRE '{sre_name}'."
            raise DataSafeHavenUserHandlingError(msg) from exc

    def remove(self, user_names: Sequence[str]) -> None:
        """Remove Entra ID and Guacamole users

        Raises:
            DataSafeHavenUserHandlingError if the users could not be removed
        """
        try:
            # Construct user lists
            self.logger.debug(f"Attempting to remove {len(user_names)} user(s).")
            entra_users_to_remove = [
                user for user in self.entra_users.list() if user.username in user_names
            ]

            # Commit changes
            self.logger.debug(
                f"Found {len(entra_users_to_remove)} valid user(s) to remove."
            )
            self.entra_users.remove(entra_users_to_remove)
        except Exception as exc:
            msg = f"Could not remove users: {user_names}."
            raise DataSafeHavenUserHandlingError(msg) from exc

    def set(self, users_csv_path: str) -> None:
        """Set Entra ID and Guacamole users

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
            entra_desired_users = [
                user
                for user in self.entra_users.list()
                if user.username in [u.username for u in desired_users]
            ]

            # Construct list of new users
            entra_desired_users = [
                user for user in desired_users if user not in entra_desired_users
            ]

            # Commit changes
            self.entra_users.set(entra_desired_users)
        except Exception as exc:
            msg = f"Could not set users from '{users_csv_path}'."
            raise DataSafeHavenUserHandlingError(msg) from exc

    def unregister(self, sre_name: str, user_names: Sequence[str]) -> None:
        """Unregister usernames with SRE

        Raises:
            DataSafeHavenUserHandlingError if the users could not be registered in the SRE
        """
        try:
            # Remove users from the SRE security group
            self.entra_users.unregister(sre_name, user_names)
        except Exception as exc:
            msg = f"Could not unregister {len(user_names)} users with SRE '{sre_name}'."
            raise DataSafeHavenUserHandlingError(msg) from exc
