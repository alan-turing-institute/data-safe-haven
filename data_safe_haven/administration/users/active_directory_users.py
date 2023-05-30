"""Interact with users in an Azure Active Directory"""
# Standard library imports
import pathlib
from typing import Any, Optional, Sequence

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.external.api import AzureApi
from data_safe_haven.helpers import FileReader, b64encode
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.pulumi import PulumiStack
from .research_user import ResearchUser


class ActiveDirectoryUsers(LoggingMixin):
    """Interact with users in an Azure Active Directory"""

    def __init__(
        self,
        config: Config,
        *args: Any,
        **kwargs: Any,
    ) -> None:
        super().__init__(*args, **kwargs)
        shm_stack = PulumiStack(config, "SHM")
        self.azure_api = AzureApi(config.subscription_name)
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
        user_details_b64 = b64encode("\n".join(csv_contents))
        output = self.azure_api.run_remote_script(
            self.resource_group_name,
            add_users_script.file_contents(),
            {"UserDetailsB64": user_details_b64},
            self.vm_name,
        )
        for line in output.split("\n"):
            self.parse_as_log(line)

    def list(self, sre_name: Optional[str] = None) -> Sequence[ResearchUser]:
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
        for line in output.split("\n"):
            tokens = line.split(";")
            if len(tokens) >= 6:
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
        return users

    def register(self, sre_name: str, usernames: Sequence[str]) -> None:
        """Register usernames with correct security group"""
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
            self.parse_as_log(line)
