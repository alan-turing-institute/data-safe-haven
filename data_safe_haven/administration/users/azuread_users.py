"""Interact with users in an Azure Active Directory"""
# Standard library imports
from typing import Sequence
import json

# Local imports
from data_safe_haven.exceptions import DataSafeHavenMicrosoftGraphException
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.helpers import GraphApi, password
from .research_user import ResearchUser


class AzureADUsers(LoggingMixin):
    """Interact with users in an Azure Active Directory"""

    def __init__(
        self,
        tenant_id,
        application_id,
        application_secret,
        research_users_group_name,
        *args,
        **kwargs,
    ):
        super().__init__(*args, **kwargs)
        self.application_id = application_id
        self.application_secret = application_secret
        self.graph_api = GraphApi(tenant_id)
        self.research_users_group_name = research_users_group_name
        self.token_ = None

    @property
    def token(self):
        if not self.token_:
            self.token_ = self.graph_api.access_token(
                self.application_id, self.application_secret
            )
        return self.token_

    @property
    def users(self) -> Sequence[ResearchUser]:
        user_list = self.graph_api.get_users(
            [
                GraphApi.linux_schema,
                "accountEnabled",
                "givenName",
                "id",
                "mail",
                "surname",
                "telephoneNumber",
                "userPrincipalName",
            ],
            self.token,
        )
        all_users = [ResearchUser.from_graph_api(**user) for user in user_list]
        return [
            user
            for user in all_users
            if user.account_enabled and not user.is_global_admin
        ]

    def add(self, new_users: Sequence[ResearchUser]) -> None:
        """Add list of users to AzureAD"""
        # Get the default domain
        default_domain = [
            domain["id"]
            for domain in self.graph_api.get_domains(self.token)
            if domain["isDefault"]
        ][0]
        for user in new_users:
            request_json = {
                "accountEnabled": user.account_enabled,
                "displayName": user.display_name,
                "givenName": user.first_name,
                "surname": user.last_name,
                "mailNickname": user.username,
                "passwordProfile": {"password": password(20)},
                "userPrincipalName": f"{user.username}@{default_domain}",
            }
            self.graph_api.create_user_with_group(
                request_json, user.email_address, user.phone_number, self.token
            )
            self.graph_api.add_user_to_group(
                user.username, self.research_users_group_name, self.token
            )
            self.info(f"Ensured user '{user.preferred_username}' exists in AzureAD")
        # Decorate all users with the Linux schema
        self.set_user_attributes()

    def remove(self, users: Sequence[ResearchUser]) -> None:
        """Disable a list of users in AzureAD"""
        for user_to_remove in users:
            matched_users = [user for user in self.users if user == user_to_remove]
            if not matched_users:
                continue
            user = matched_users[0]
            try:
                if self.graph_api.remove_user_from_group(
                    user.username, self.research_users_group_name, self.token
                ):
                    self.info(
                        f"Removed '{user.preferred_username}' from group '{self.research_users_group_name}'"
                    )
                else:
                    raise DataSafeHavenMicrosoftGraphException
            except DataSafeHavenMicrosoftGraphException:
                self.error(
                    f"Unable to remove '{user.preferred_username}' from group '{self.research_users_group_name}'"
                )

    def set(self, users: Sequence[ResearchUser]) -> None:
        """Set Guacamole users to specified list"""
        users_to_remove = [user for user in self.users if user not in users]
        self.remove(users_to_remove)
        users_to_add = [user for user in users if user not in self.users]
        self.add(users_to_add)

    def set_user_attributes(self):
        """Ensure that all users have Linux attributes"""
        next_uid = max(
            [int(user.uid_number) + 1 if user.uid_number else 0 for user in self.users]
            + [10000]
        )
        for user in self.users:
            # Get username from userPrincipalName
            username = user.user_principal_name.split("@")[0]
            if not user.homedir:
                user.homedir = f"/home/{username}"
                self.debug(
                    f"Added homedir {user.homedir} to user {user.preferred_username}"
                )
            if not user.shell:
                user.shell = "/bin/bash"
                self.debug(
                    f"Added shell {user.shell} to user {user.preferred_username}"
                )
            if not user.uid_number:
                # Set UID to the next unused one
                user.uid_number = next_uid
                next_uid += 1
                self.debug(
                    f"Added uid {user.uid_number} to user {user.preferred_username}"
                )
            if not user.username:
                user.username = username
                self.debug(
                    f"Added username {user.username} to user {user.preferred_username}"
                )
            # Ensure that the remote user matches the local model
            patch_json = {
                GraphApi.linux_schema: {
                    "gidnumber": user.uid_number,
                    "homedir": user.homedir,
                    "shell": user.shell,
                    "uid": user.uid_number,
                    "user": user.username,
                }
            }
            try:
                self.graph_api.http_patch(
                    f"{self.graph_api.base_endpoint}/users/{user.azure_oid}",
                    headers={"Authorization": f"Bearer {self.token}"},
                    json=patch_json,
                )
                self.debug(f"Set Linux attributes for user {user.preferred_username}.")
            except DataSafeHavenMicrosoftGraphException as exc:
                self.error(
                    f"Failed to set Linux attributes for user {user.preferred_username}: {str(exc)}"
                )
