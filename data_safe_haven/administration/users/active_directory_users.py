"""Interact with users in an Azure Active Directory"""
# Standard library imports
import pathlib
from typing import Sequence

# Local imports
from data_safe_haven.external import AzureApi
from data_safe_haven.helpers import FileReader
from data_safe_haven.mixins import LoggingMixin
from .research_user import ResearchUser


class ActiveDirectoryUsers(LoggingMixin):
    """Interact with users in an Azure Active Directory"""

    def __init__(
        self,
        resource_group_name,
        subscription_name,
        vm_name,
        *args,
        **kwargs,
    ):
        super().__init__(*args, **kwargs)
        self.azure_api = AzureApi(subscription_name)
        self.resource_group_name = resource_group_name
        self.resources_path = (
            pathlib.Path(__file__).parent.parent.parent / "resources"
        ).resolve()
        self.vm_name = vm_name

    def list(self) -> Sequence[ResearchUser]:
        """List users in a local Active Directory"""
        list_users_script = FileReader(
            self.resources_path / "active_directory" / "list_users.ps1"
        )
        output = self.azure_api.run_remote_script(
            self.resource_group_name,
            list_users_script.file_contents(),
            {},
            self.vm_name,
        )

        users = []
        for line in output.split("\n"):
            tokens = line.split(";")
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
