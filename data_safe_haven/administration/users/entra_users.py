"""Interact with users in Entra ID."""

from collections.abc import Sequence

from data_safe_haven.exceptions import (
    DataSafeHavenEntraIDError,
    DataSafeHavenError,
    DataSafeHavenTypeError,
)
from data_safe_haven.external import GraphApi
from data_safe_haven.functions import password
from data_safe_haven.logging import get_logger

from .research_user import ResearchUser


class EntraUsers:
    """Interact with users in Entra ID."""

    def __init__(
        self,
        graph_api: GraphApi,
    ) -> None:
        self.graph_api = graph_api
        self.logger = get_logger()

    def add(self, new_users: Sequence[ResearchUser]) -> None:
        """
        Add list of users to Entra ID

        Raises:
            DataSafeHavenEntraIDError if any user could not be created
        """
        try:
            available_domains = {
                domain["id"]
                for domain in self.graph_api.read_domains()
                if domain["isVerified"]
            }
            for user in new_users:
                if user.domain not in available_domains:
                    msg = f"Domain '[green]{user.domain}[/]' is not verified."
                    raise DataSafeHavenTypeError(msg)
                request_json = {
                    "accountEnabled": user.account_enabled,
                    "displayName": user.display_name,
                    "givenName": user.given_name,
                    "surname": user.surname,
                    "mailNickname": user.username,
                    "passwordProfile": {"password": password(20)},
                    "userPrincipalName": f"{user.username}@{user.domain}",
                }
                if not user.email_address:
                    msg = (
                        f"User '[green]{user.username}[/]' is missing an email address."
                    )
                    raise DataSafeHavenTypeError(msg)
                if not user.phone_number:
                    msg = f"User '[green]{user.username}[/]' is missing a phone number."
                    raise DataSafeHavenTypeError(msg)
                self.graph_api.create_user(
                    request_json, user.email_address, user.phone_number
                )
                self.logger.info(
                    f"Ensured user '[green]{user.preferred_username}[/]' exists in Entra ID"
                )
        except DataSafeHavenError as exc:
            msg = "Unable to add users to Entra ID."
            raise DataSafeHavenEntraIDError(msg) from exc

    def list(self) -> Sequence[ResearchUser]:
        """
        List available Entra users

        Raises:
            DataSafeHavenEntraIDError if users could not be loaded
        """
        try:
            user_list = self.graph_api.read_users()
            return [
                ResearchUser(
                    account_enabled=user_details["accountEnabled"],
                    email_address=user_details["mail"],
                    given_name=user_details["givenName"],
                    phone_number=(
                        user_details["businessPhones"][0]
                        if len(user_details["businessPhones"])
                        else None
                    ),
                    sam_account_name=(
                        user_details["onPremisesSamAccountName"]
                        if user_details["onPremisesSamAccountName"]
                        else user_details["mailNickname"]
                    ),
                    surname=user_details["surname"],
                    user_principal_name=user_details["userPrincipalName"],
                )
                for user_details in user_list
            ]
        except DataSafeHavenError as exc:
            msg = "Unable to list Entra ID users."
            raise DataSafeHavenEntraIDError(msg) from exc

    def register(self, sre_name: str, usernames: Sequence[str]) -> None:
        """
        Add usernames to SRE group in Entra ID

        Raises:
            DataSafeHavenEntraIDError if any user could not be added to the group.
        """
        try:
            group_name = f"Data Safe Haven SRE {sre_name} Users"
            for username in usernames:
                self.graph_api.add_user_to_group(username, group_name)
        except DataSafeHavenError as exc:
            msg = f"Unable to add users to group '{group_name}'."
            raise DataSafeHavenEntraIDError(msg) from exc

    def remove(self, users: Sequence[ResearchUser]) -> None:
        """
        Remove list of users from Entra ID

        Raises:
            DataSafeHavenEntraIDError if any user could not be removed.
        """
        try:
            for user in filter(
                lambda existing_user: any(existing_user == user for user in users),
                self.list(),
            ):
                self.graph_api.remove_user(user.username)
                self.logger.info(f"Removed '{user.preferred_username}'.")
        except DataSafeHavenError as exc:
            msg = "Unable to remove users from Entra ID."
            raise DataSafeHavenEntraIDError(msg) from exc

    def set(self, users: Sequence[ResearchUser]) -> None:
        """
        Set Entra users to specified list

        Raises:
            DataSafeHavenEntraIDError if user list could not be set
        """
        try:
            users_to_remove = [user for user in self.list() if user not in users]
            self.remove(users_to_remove)
            users_to_add = [user for user in users if user not in self.list()]
            self.add(users_to_add)
        except DataSafeHavenError as exc:
            msg = "Unable to set desired user list in Entra ID."
            raise DataSafeHavenEntraIDError(msg) from exc

    def unregister(self, sre_name: str, usernames: Sequence[str]) -> None:
        """
        Remove usernames from SRE group in Entra ID

        Raises:
            DataSafeHavenEntraIDError if any user could not be added to the group.
        """
        try:
            group_name = f"Data Safe Haven SRE {sre_name}"
            for username in usernames:
                self.graph_api.remove_user_from_group(username, group_name)
        except DataSafeHavenError as exc:
            msg = f"Unable to remove users from group {group_name}."
            raise DataSafeHavenEntraIDError(msg) from exc
