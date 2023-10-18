"""Interact with users in an Azure Active Directory"""
import pathlib
from collections.abc import Sequence
from typing import Any

from data_safe_haven.config import Config
from data_safe_haven.exceptions import DataSafeHavenActiveDirectoryError
from data_safe_haven.external import AzureApi
from data_safe_haven.functions import b64encode
from data_safe_haven.infrastructure import PulumiAccount, SHMStackManager
from data_safe_haven.utility import FileReader, LoggingSingleton

from .research_user import ResearchUser


class ActiveDirectoryUsers:
    """Interact with users in an Azure Active Directory"""

    def __init__(
        self,
        config: Config,
        *args: Any,
        **kwargs: Any,
    ) -> None:
        super().__init__(*args, **kwargs)
        account = PulumiAccount(config)
        account.handle_login()
        shm_stack = SHMStackManager(config)
        self.azure_api = AzureApi(config.subscription_name)
        self.logger = LoggingSingleton()
        self.resource_group_name = shm_stack.output("domain_controllers")[
            "resource_group_name"
        ]
        self.resources_path = (
            pathlib.Path(__file__).parent.parent.parent / "resources"
        ).resolve()
        self.vm_name = shm_stack.output("domain_controllers")["vm_name"]

    def add(self, new_users: Sequence[ResearchUser]) -> None:
        """Add list of users to local Active Directory"""
        add_users_script = FileReader(
            self.resources_path / "active_directory" / "add_users.ps1"
        )
        csv_contents = ["SamAccountName;GivenName;Surname;Mobile;Email;Country"]
        for user in new_users:
            if (
                user.username
                and user.given_name
                and user.surname
                and user.phone_number
                and user.email_address
                and user.country
            ):
                csv_contents += [
                    ";".join(
                        [
                            user.username,
                            user.given_name,
                            user.surname,
                            user.phone_number,
                            user.email_address,
                            user.country,
                        ]
                    )
                ]
            else:
                msg = (
                    f"User {user.username} does not have all the required fields to "
                    "add to the Active Directory."
                )
                raise DataSafeHavenActiveDirectoryError(msg)
        user_details_b64 = b64encode("\n".join(csv_contents))
        output = self.azure_api.run_remote_script(
            self.resource_group_name,
            add_users_script.file_contents(),
            {"UserDetailsB64": user_details_b64},
            self.vm_name,
        )
        for line in output.split("\n"):
            self.logger.parse(line)

    def list(self, sre_name: str | None = None) -> Sequence[ResearchUser]:  # noqa: A003
        """List users in a local Active Directory"""
        list_users_script = FileReader(
            self.resources_path / "active_directory" / "list_users.ps1"
        )
        script_params = {"SREName": sre_name} if sre_name else {}
        output = self.azure_api.run_remote_script(
            self.resource_group_name,
            list_users_script.file_contents(),
            script_params,
            self.vm_name,
        )
        users = []
        expected_columns = 6
        for line in output.split("\n"):
            tokens = line.split(";")
            if (n_tokens := len(tokens)) == expected_columns:
                users.append(
                    ResearchUser(
                        email_address=tokens[4],
                        given_name=tokens[1],
                        phone_number=tokens[3],
                        sam_account_name=tokens[0],
                        surname=tokens[2],
                        user_principal_name=tokens[5],
                    )
                )
            else:
                msg = (
                    "Unexpected number of  fields returned for Active Directory user.\n"
                    f"Expected {expected_columns}, got {n_tokens}:\n"
                    f"{tokens}"
                )
                raise DataSafeHavenActiveDirectoryError(msg)
        return users

    def register(self, sre_name: str, usernames: Sequence[str]) -> None:
        """Add usernames to SRE security group"""
        register_users_script = FileReader(
            self.resources_path / "active_directory" / "add_users_to_group.ps1"
        )
        output = self.azure_api.run_remote_script(
            self.resource_group_name,
            register_users_script.file_contents(),
            {"SREName": sre_name, "UsernamesB64": b64encode("\n".join(usernames))},
            self.vm_name,
        )
        for line in output.split("\n"):
            self.logger.parse(line)

    def remove(self, users: Sequence[ResearchUser]) -> None:
        """Remove list of users from local Active Directory"""
        remove_users_script = FileReader(
            self.resources_path / "active_directory" / "remove_users.ps1"
        )
        usernames_b64 = b64encode("\n".join(user.username for user in users))
        output = self.azure_api.run_remote_script(
            self.resource_group_name,
            remove_users_script.file_contents(),
            {"UsernamesB64": usernames_b64},
            self.vm_name,
        )
        for line in output.split("\n"):
            self.logger.parse(line)

    def set(self, users: Sequence[ResearchUser]) -> None:  # noqa: A003
        """Set local Active Directory users to specified list"""
        users_to_remove = [user for user in self.list() if user not in users]
        self.remove(users_to_remove)
        users_to_add = [user for user in users if user not in self.list()]
        self.add(users_to_add)

    def unregister(self, sre_name: str, usernames: Sequence[str]) -> None:
        """Remove usernames from SRE security group"""
        register_users_script = FileReader(
            self.resources_path / "active_directory" / "remove_users_from_group.ps1"
        )
        output = self.azure_api.run_remote_script(
            self.resource_group_name,
            register_users_script.file_contents(),
            {"SREName": sre_name, "UsernamesB64": b64encode("\n".join(usernames))},
            self.vm_name,
        )
        for line in output.split("\n"):
            self.logger.parse(line)
