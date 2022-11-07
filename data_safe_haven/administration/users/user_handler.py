# Standard library imports
import csv
from typing import Sequence

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.exceptions import DataSafeHavenUserHandlingException
from data_safe_haven.external import GraphApi
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
        *args,
        **kwargs,
    ):
        super().__init__(subscription_name=config.subscription_name, *args, **kwargs)
        self.active_directory_users = ActiveDirectoryUsers(
            resource_group_name=config.shm.domain_controllers.resource_group_name,
            subscription_name=config.subscription_name,
            vm_name=config.shm.domain_controllers.vm_name,
        )
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
            with open(users_csv_path) as f_csv:
                reader = csv.DictReader(f_csv)
                for required_field in ["GivenName", "Surname", "Phone", "Email"]:
                    if required_field not in reader.fieldnames:
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
            )

    def list(self) -> None:
        """List Active Directory, AzureAD and Guacamole users

        Raises:
            DataSafeHavenUserHandlingException if the users could not be listed
        """
        try:
            # Load usernames
            usernames = {}
            usernames["Azure AD"] = [
                user.username for user in self.azure_ad_users.list()
            ]
            usernames["Domain controller"] = [
                user.username for user in self.active_directory_users.list()
            ]
            for sre_name, guacamole_users in self.sre_guacamole_users.items():
                usernames[f"SRE {sre_name}"] = [
                    user.username for user in guacamole_users.list()
                ]

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
            guacamole_users = [
                user for user in self.guacamole.users if user in new_users
            ]

            # Add any new users
            azuread_users += [user for user in new_users if user not in azuread_users]
            guacamole_users += [
                user for user in new_users if user not in guacamole_users
            ]

            # Commit changes
            self.azuread.set(azuread_users)
            self.guacamole.set(guacamole_users)
        except Exception as exc:
            raise DataSafeHavenUserHandlingException(
                f"Could not set users from '{users_csv_path}'.\n{str(exc)}"
            )
