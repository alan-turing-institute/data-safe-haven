"""Interface to the Microsoft Graph API"""

import datetime
import json
import time
from collections.abc import Sequence
from contextlib import suppress
from typing import Any, ClassVar, Self

import requests
import typer
from dns import resolver

from data_safe_haven import console
from data_safe_haven.exceptions import (
    DataSafeHavenMicrosoftGraphError,
    DataSafeHavenValueError,
)
from data_safe_haven.logging import get_logger, get_null_logger

from .credentials import DeferredCredential, GraphApiCredential


class GraphApi:
    """Interface to the Microsoft Graph REST API"""

    application_ids: ClassVar[dict[str, str]] = {
        "Microsoft Graph": "00000003-0000-0000-c000-000000000000",
    }
    role_template_ids: ClassVar[dict[str, str]] = {
        "Global Administrator": "62e90394-69f5-4237-9190-012177145e10"
    }
    uuid_application: ClassVar[dict[str, str]] = {
        "Application.ReadWrite.All": "1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9",
        "AppRoleAssignment.ReadWrite.All": "06b708a9-e830-4db3-a914-8e69da51d44f",
        "Directory.Read.All": "7ab1d382-f21e-4acd-a863-ba3e13f7da61",
        "Domain.Read.All": "dbb9058a-0e50-45d7-ae91-66909b5d4664",
        "Group.Read.All": "5b567255-7703-4780-807c-7be8301ae99b",
        "Group.ReadWrite.All": "62a82d76-70ea-41e2-9197-370581804d09",
        "GroupMember.Read.All": "98830695-27a2-44f7-8c18-0c3ebc9698f6",
        "GroupMember.ReadWrite.All": "dbaae8cf-10b5-4b86-a4a1-f871c94c6695",
        "User.Read.All": "df021288-bdef-4463-88db-98f22de89214",
        "User.ReadWrite.All": "741f803b-c850-494e-b5df-cde7c675a1ca",
        "UserAuthenticationMethod.ReadWrite.All": "50483e42-d915-4231-9639-7fdb7fd190e5",
    }
    uuid_delegated: ClassVar[dict[str, str]] = {
        "GroupMember.Read.All": "bc024368-1153-4739-b217-4326f2e966d0",
        "User.Read.All": "a154be20-db9c-4678-8ab7-66f6cc099a59",
    }

    def __init__(
        self,
        *,
        credential: DeferredCredential,
        disable_logging: bool = False,
    ):
        self.base_endpoint = "https://graph.microsoft.com/v1.0"
        self.credential = credential
        self.logger = get_null_logger() if disable_logging else get_logger()

    @classmethod
    def from_scopes(
        cls: type[Self],
        *,
        scopes: Sequence[str],
        tenant_id: str,
        disable_logging: bool = False,
    ) -> "GraphApi":
        return cls(
            credential=GraphApiCredential(
                scopes=scopes, tenant_id=tenant_id, skip_confirmation=disable_logging
            ),
            disable_logging=disable_logging,
        )

    @classmethod
    def from_token(
        cls: type[Self], auth_token: str, *, disable_logging: bool = False
    ) -> "GraphApi":
        """Construct a GraphApi from an existing authentication token."""
        try:
            decoded = DeferredCredential.decode_token(auth_token)
            return cls.from_scopes(
                disable_logging=disable_logging,
                scopes=str(decoded["scp"]).split(),
                tenant_id=decoded["tid"],
            )
        except DataSafeHavenValueError as exc:
            msg = "Could not construct GraphApi from provided token."
            raise DataSafeHavenValueError(msg) from exc

    @property
    def token(self) -> str:
        return self.credential.token

    def add_custom_domain(self, domain_name: str) -> str:
        """Add Entra ID custom domain

        Returns:
            str: Registration TXT record

        Raises:
            DataSafeHavenMicrosoftGraphError if domain could not be added
        """
        try:
            # Create the Entra ID custom domain if it does not already exist
            domains = self.read_domains()
            if not any(domain["id"] == domain_name for domain in domains):
                self.http_post(
                    f"{self.base_endpoint}/domains",
                    json={"id": domain_name},
                )
            # Get the DNS verification records for the custom domain
            response = self.http_get(
                f"{self.base_endpoint}/domains/{domain_name}/verificationDnsRecords"
            )
            txt_records: list[str] = [
                record["text"]
                for record in response.json()["value"]
                if record["recordType"] == "Txt"
            ]
            if not txt_records:
                msg = f"Could not retrieve verification DNS records for {domain_name}."
                raise DataSafeHavenMicrosoftGraphError(msg)
            return txt_records[0]
        except Exception as exc:
            msg = f"Could not register domain '{domain_name}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def add_user_to_group(
        self,
        username: str,
        group_name: str,
    ) -> None:
        """Add a user to a group

        Raises:
            DataSafeHavenMicrosoftGraphError if the user could not be added to the group.
        """
        try:
            user_id = self.get_id_from_username(username)
            group_id = self.validate_entra_group(group_name)
            json_response = self.http_get(
                f"{self.base_endpoint}/groups/{group_id}/members",
            ).json()
            # If user already belongs to group then do nothing further
            if any(user_id == member["id"] for member in json_response["value"]):
                self.logger.info(
                    f"User [green]'{username}'[/] is already a member of group [green]'{group_name}'[/]."
                )
            # Otherwise add the user to the group
            else:
                request_json = {
                    "@odata.id": f"https://graph.microsoft.com/v1.0/directoryObjects/{user_id}"
                }
                self.http_post(
                    f"{self.base_endpoint}/groups/{group_id}/members/$ref",
                    json=request_json,
                )
                self.logger.info(
                    f"Added user [green]'{username}'[/] to group [green]'{group_name}'[/]."
                )
        except DataSafeHavenMicrosoftGraphError as exc:
            msg = f"Could not add user '{username}' to group '{group_name}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def create_application(
        self,
        application_name: str,
        application_scopes: Sequence[str] = [],
        delegated_scopes: Sequence[str] = [],
        request_json: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Create an Entra application if it does not already exist

        Raises:
            DataSafeHavenMicrosoftGraphError if the application could not be created
        """
        try:
            # Check for an existing application
            json_response: dict[str, Any]
            if existing_application := self.get_application_by_name(application_name):
                self.logger.info(
                    f"Application '[green]{application_name}[/]' already exists."
                )
                json_response = existing_application
            else:
                # Create a new application
                self.logger.debug(
                    f"Creating new application '[green]{application_name}[/]'...",
                )
                if not request_json:
                    request_json = {
                        "displayName": application_name,
                        "signInAudience": "AzureADMyOrg",
                        "passwordCredentials": [],
                        "publicClient": {
                            "redirectUris": [
                                "https://login.microsoftonline.com/common/oauth2/nativeclient",
                                "urn:ietf:wg:oauth:2.0:oob",
                            ]
                        },
                    }
                # Add scopes if there are any
                scopes = [
                    {
                        "id": self.uuid_application[application_scope],
                        "type": "Role",  # 'Role' is the type for application permissions
                    }
                    for application_scope in application_scopes
                ] + [
                    {
                        "id": self.uuid_delegated[delegated_scope],
                        "type": "Scope",  # 'Scope' is the type for delegated permissions
                    }
                    for delegated_scope in delegated_scopes
                ]
                if scopes:
                    request_json["requiredResourceAccess"] = [
                        {
                            "resourceAppId": self.application_ids["Microsoft Graph"],
                            "resourceAccess": scopes,
                        }
                    ]
                self.logger.debug("Making creation HTTP POST request.")
                json_response = self.http_post(
                    f"{self.base_endpoint}/applications",
                    json=request_json,
                ).json()
                self.logger.info(
                    f"Created new application '[green]{json_response['displayName']}[/]'.",
                )

            # Ensure that the application service principal exists
            self.ensure_application_service_principal(application_name)

            # Grant admin consent for the requested scopes
            if application_scopes or delegated_scopes:
                for scope in application_scopes:
                    self.grant_application_role_permissions(application_name, scope)
                for scope in delegated_scopes:
                    self.grant_delegated_role_permissions(application_name, scope)
                attempts = 0
                max_attempts = 5
                while attempts < max_attempts:
                    if application_sp := self.get_service_principal_by_name(
                        application_name
                    ):
                        if self.read_application_permissions(application_sp["id"]):
                            break
                    time.sleep(10)
                    attempts += 1

                if attempts == max_attempts:
                    msg = "Maximum attempts to validate service principle permissions exceeded"
                    raise DataSafeHavenMicrosoftGraphError(msg)

            # Return JSON representation of the Entra application
            return json_response
        except Exception as exc:
            msg = f"Could not create application '{application_name}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def create_application_secret(
        self, application_name: str, application_secret_name: str
    ) -> str:
        """Add a secret to an existing Entra application, overwriting any existing secret.

        Returns:
            str: Contents of newly-created secret

        Raises:
            DataSafeHavenMicrosoftGraphError if the secret could not be created
        """
        try:
            application_json = self.get_application_by_name(application_name)
            if not application_json:
                msg = f"Could not retrieve application '{application_name}'"
                raise DataSafeHavenMicrosoftGraphError(msg)
            # If the secret already exists then remove it
            if "passwordCredentials" in application_json:
                for secret in application_json["passwordCredentials"]:
                    if secret["displayName"] == application_secret_name:
                        self.logger.debug(
                            f"Removing pre-existing secret '{secret['displayName']}' from application '{application_name}'."
                        )
                        self.http_post(
                            f"{self.base_endpoint}/applications/{application_json['id']}/removePassword",
                            json={"keyId": secret["keyId"]},
                        )
            # Create the application secret
            self.logger.debug(
                f"Creating application secret '[green]{application_secret_name}[/]'...",
            )
            request_json = {
                "passwordCredential": {
                    "displayName": application_secret_name,
                    "endDateTime": (
                        datetime.datetime.now(datetime.UTC)
                        + datetime.timedelta(weeks=520)
                    ).strftime("%Y-%m-%dT%H:%M:%SZ"),
                }
            }
            json_response = self.http_post(
                f"{self.base_endpoint}/applications/{application_json['id']}/addPassword",
                json=request_json,
            ).json()
            self.logger.debug(
                f"Created application secret '[green]{application_secret_name}[/]'.",
            )
            return str(json_response["secretText"])
        except Exception as exc:
            msg = f"Could not create application secret '{application_secret_name}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def ensure_application_service_principal(
        self, application_name: str
    ) -> dict[str, Any]:
        """Create a service principal for an Entra application if it does not already exist

        Raises:
            DataSafeHavenMicrosoftGraphError if the service principal could not be created
        """
        try:
            # Return existing service principal if there is one
            application_sp = self.get_service_principal_by_name(application_name)
            if not application_sp:
                # Otherwise we need to try
                self.logger.debug(
                    f"Creating service principal for application '[green]{application_name}[/]'...",
                )
                application_json = self.get_application_by_name(application_name)
                if not application_json:
                    msg = f"Could not retrieve application '{application_name}'"
                    raise DataSafeHavenMicrosoftGraphError(msg)
                self.http_post(
                    f"{self.base_endpoint}/servicePrincipals",
                    json={"appId": application_json["appId"]},
                ).json()
                self.logger.info(
                    f"Created service principal for application '[green]{application_name}[/]'.",
                )
                application_sp = self.get_service_principal_by_name(application_name)
                if not application_sp:
                    msg = f"service principal for application '[green]{application_name}[/]' not found."
                    raise DataSafeHavenMicrosoftGraphError(msg)
            return application_sp
        except Exception as exc:
            msg = f"Could not create service principal for application '{application_name}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def create_user(
        self,
        request_json: dict[str, Any],
        email_address: str,
        phone_number: str,
    ) -> None:
        """Create an Entra user if it does not already exist

        Raises:
            DataSafeHavenMicrosoftGraphError if the user could not be created
        """
        username = request_json["mailNickname"]
        final_verb = "create/update"
        try:
            # Check whether user already exists
            user_id = self.get_id_from_username(username)
            if user_id:
                self.logger.debug(
                    f"Updating Entra user '[green]{username}[/]'...",
                )
                final_verb = "Update"
            else:
                self.logger.debug(
                    f"Creating Entra user '[green]{username}[/]'...",
                )
                final_verb = "Create"
                # If they do not then create them
                endpoint = f"{self.base_endpoint}/users"
                json_response = self.http_post(
                    endpoint,
                    json=request_json,
                ).json()
                user_id = json_response["id"]
            # Set the authentication email address
            try:
                response = self.http_get(
                    f"https://graph.microsoft.com/beta/users/{user_id}/authentication/emailMethods"
                )
                if existing_email_addresses := [
                    item["emailAddress"] for item in response.json()["value"]
                ]:
                    self.logger.warning(
                        f"Email authentication is already set up for Entra user '[green]{username}[/]' using {existing_email_addresses}."
                    )
                else:
                    self.http_post(
                        f"https://graph.microsoft.com/beta/users/{user_id}/authentication/emailMethods",
                        json={"emailAddress": email_address},
                    )
            except DataSafeHavenMicrosoftGraphError as exc:
                msg = f"Failed to add authentication email address '{email_address}'."
                raise DataSafeHavenMicrosoftGraphError(msg) from exc

            # Set the authentication phone number
            try:
                response = self.http_get(
                    f"https://graph.microsoft.com/beta/users/{user_id}/authentication/phoneMethods"
                )
                if existing_phone_numbers := [
                    item["phoneNumber"] for item in response.json()["value"]
                ]:
                    self.logger.warning(
                        f"Phone authentication is already set up for Entra user '[green]{username}[/]' using {existing_phone_numbers}."
                    )
                else:
                    self.http_post(
                        f"https://graph.microsoft.com/beta/users/{user_id}/authentication/phoneMethods",
                        json={"phoneNumber": phone_number, "phoneType": "mobile"},
                    )
            except DataSafeHavenMicrosoftGraphError as exc:
                msg = f"Failed to add authentication phone number '{phone_number}'."
                raise DataSafeHavenMicrosoftGraphError(msg) from exc
            # Ensure user is enabled
            self.http_patch(
                f"{self.base_endpoint}/users/{user_id}",
                json={"accountEnabled": True},
            )
            self.logger.info(
                f"{final_verb}d Entra user '[green]{username}[/]'.",
            )
        except DataSafeHavenMicrosoftGraphError as exc:
            msg = f"Could not {final_verb.lower()} user {username}."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def delete_application(
        self,
        application_name: str,
    ) -> None:
        """Remove an application from Entra ID

        Raises:
            DataSafeHavenMicrosoftGraphError if the application could not be deleted
        """
        try:
            # Delete the application if it exists
            if application := self.get_application_by_name(application_name):
                self.logger.debug(
                    f"Deleting application '[green]{application_name}[/]'...",
                )
                self.http_delete(
                    f"{self.base_endpoint}/applications/{application['id']}",
                )
                self.logger.info(
                    f"Deleted application '[green]{application_name}[/]'.",
                )
        except Exception as exc:
            msg = f"Could not delete application '{application_name}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def get_application_by_name(self, application_name: str) -> dict[str, Any] | None:
        try:
            return next(
                application
                for application in self.read_applications()
                if application["displayName"] == application_name
            )
        except (DataSafeHavenMicrosoftGraphError, StopIteration):
            return None

    def get_service_principal_by_name(
        self, service_principal_name: str
    ) -> dict[str, Any] | None:
        try:
            return next(
                service_principal
                for service_principal in self.read_service_principals()
                if service_principal["displayName"] == service_principal_name
            )
        except (DataSafeHavenMicrosoftGraphError, StopIteration):
            return None

    def validate_entra_group(self, group_name: str) -> str:
        """
        Ensure that an Entra group exists and return its ID

        Raises:
            DataSafeHavenMicrosoftGraphError if the group does not exist
        """
        if group_id := self.get_id_from_groupname(group_name):
            return group_id
        else:
            msg = f"Group '{group_name}' not found."
            raise DataSafeHavenMicrosoftGraphError(msg)

    def get_id_from_groupname(self, group_name: str) -> str | None:
        try:
            return str(
                next(
                    group
                    for group in self.read_groups()
                    if group["displayName"] == group_name
                )["id"]
            )
        except (DataSafeHavenMicrosoftGraphError, StopIteration):
            return None

    def get_id_from_username(self, username: str) -> str | None:
        try:
            return str(
                next(
                    user
                    for user in self.read_users()
                    if user["userPrincipalName"].split("@")[0] == username
                )["id"]
            )
        except (DataSafeHavenMicrosoftGraphError, StopIteration):
            return None

    def grant_role_permissions(
        self,
        application_name: str,
        *,
        application_role_assignments: Sequence[str],
        delegated_role_assignments: Sequence[str],
    ) -> None:
        """
        Grant roles to the service principal associated with an application and give admin approval to these roles

        These can be either application or delegated roles.

        - Application roles allow the application to perform an action itself.
        - Delegated roles allow the application to ask a user for permission to perform an action.

        See https://learn.microsoft.com/en-us/graph/permissions-grant-via-msgraph for more details.

        Raises:
            DataSafeHavenMicrosoftGraphError if one or more roles could not be assigned.
        """
        # Ensure that the application has a service principal
        self.ensure_application_service_principal(application_name)

        # Grant any requested application role permissions
        for role_name in application_role_assignments:
            self.grant_application_role_permissions(application_name, role_name)

        # Grant any requested delegated role permissions
        for role_name in delegated_role_assignments:
            self.grant_delegated_role_permissions(application_name, role_name)

    def grant_application_role_permissions(
        self, application_name: str, application_role_name: str
    ) -> None:
        """
        Assign a named application role to the service principal associated with an application.
        Additionally provide Global Admin approval for the application to hold this role.
        Application roles allow the application to perform an action itself.

        See https://learn.microsoft.com/en-us/graph/permissions-grant-via-msgraph for more details.

        Raises:
            DataSafeHavenMicrosoftGraphError if one or more roles could not be assigned.
        """
        try:
            # Get service principals for Microsoft Graph and this application
            microsoft_graph_sp = self.get_service_principal_by_name("Microsoft Graph")
            if not microsoft_graph_sp:
                msg = "Could not find Microsoft Graph service principal."
                raise DataSafeHavenMicrosoftGraphError(msg)
            application_sp = self.get_service_principal_by_name(application_name)
            if not application_sp:
                msg = f"Could not find application service principal for application {application_name}."
                raise DataSafeHavenMicrosoftGraphError(msg)
            # Check whether permission is already granted
            app_role_id = self.uuid_application[application_role_name]
            response = self.http_get(
                f"{self.base_endpoint}/servicePrincipals/{microsoft_graph_sp['id']}/appRoleAssignedTo",
            )
            for application in response.json().get("value", []):
                if (application["appRoleId"] == app_role_id) and (
                    application["principalDisplayName"] == application_name
                ):
                    self.logger.debug(
                        f"Application role '[green]{application_role_name}[/]' already assigned to '{application_name}'.",
                    )
                    return
            # Otherwise grant permissions for this role to the application
            self.logger.debug(
                f"Assigning application role '[green]{application_role_name}[/]' to '{application_name}'...",
            )
            request_json = {
                "principalId": application_sp["id"],
                "resourceId": microsoft_graph_sp["id"],
                "appRoleId": app_role_id,
            }
            self.http_post(
                f"{self.base_endpoint}/servicePrincipals/{microsoft_graph_sp['id']}/appRoleAssignments",
                json=request_json,
            )
            self.logger.info(
                f"Assigned application role '[green]{application_role_name}[/]' to '{application_name}'.",
            )
        except Exception as exc:
            msg = f"Could not assign application role '{application_role_name}' to application '{application_name}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def grant_delegated_role_permissions(
        self, application_name: str, application_role_name: str
    ) -> None:
        """
        Assign a named delegated role to the service principal associated with an application.
        Additionally provide Global Admin approval for the application to hold this role.
        Delegated roles allow the application to ask a user for permission to perform an action.

        See https://learn.microsoft.com/en-us/graph/permissions-grant-via-msgraph for more details.

        Raises:
            DataSafeHavenMicrosoftGraphError if one or more roles could not be assigned.
        """
        try:
            # Get service principals for Microsoft Graph and this application
            microsoft_graph_sp = self.get_service_principal_by_name("Microsoft Graph")
            if not microsoft_graph_sp:
                msg = "Could not find Microsoft Graph service principal."
                raise DataSafeHavenMicrosoftGraphError(msg)
            application_sp = self.get_service_principal_by_name(application_name)
            if not application_sp:
                msg = "Could not find application service principal."
                raise DataSafeHavenMicrosoftGraphError(msg)
            # Check existing permissions
            response = self.http_get(f"{self.base_endpoint}/oauth2PermissionGrants")
            self.logger.debug(
                f"Assigning delegated role '[green]{application_role_name}[/]' to '{application_name}'...",
            )
            # If there are existing permissions then we need to patch
            application = next(
                (
                    app
                    for app in response.json().get("value", [])
                    if app["clientId"] == application_sp["id"]
                ),
                None,
            )
            if application:
                request_json = {
                    "scope": f"{application['scope']} {application_role_name}"
                }
                response = self.http_patch(
                    f"{self.base_endpoint}/oauth2PermissionGrants/{application['id']}",
                    json=request_json,
                )
            # Otherwise we need to make a new delegation request
            else:
                request_json = {
                    "clientId": application_sp["id"],
                    "consentType": "AllPrincipals",
                    "resourceId": microsoft_graph_sp["id"],
                    "scope": application_role_name,
                }
                response = self.http_post(
                    f"{self.base_endpoint}/oauth2PermissionGrants",
                    json=request_json,
                )
            self.logger.info(
                f"Assigned delegated role '[green]{application_role_name}[/]' to '{application_name}'.",
            )
        except Exception as exc:
            msg = f"Could not assign delegated role '{application_role_name}' to application '{application_name}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    @staticmethod
    def http_raise_for_status(response: requests.Response) -> None:
        """Check the status of a response

        Raises:
            RequestException if the response did not succeed
        """
        # We do not use response.ok as this allows 3xx codes
        if requests.codes.OK <= response.status_code < requests.codes.MULTIPLE_CHOICES:
            return
        raise requests.exceptions.RequestException(
            response=response, request=response.request
        )

    def http_delete(self, url: str, **kwargs: Any) -> requests.Response:
        """Make an HTTP DELETE request

        Returns:
            requests.Response: The response from the remote server

        Raises:
            DataSafeHavenMicrosoftGraphError if the request failed
        """
        try:
            response = requests.delete(
                url,
                headers={"Authorization": f"Bearer {self.token}"},
                timeout=120,
                **kwargs,
            )
            self.http_raise_for_status(response)
            return response

        except requests.exceptions.RequestException as exc:
            msg = f"Could not execute DELETE request to '{url}'."
            if exc.response:
                msg += f" Response content received: '{exc.response.content.decode()}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def http_get_single_page(self, url: str, **kwargs: Any) -> requests.Response:
        """Make an HTTP GET request

        Returns:
            requests.Response: The response from the remote server

        Raises:
            DataSafeHavenMicrosoftGraphError if the request failed
        """
        try:
            response = requests.get(
                url,
                headers={"Authorization": f"Bearer {self.token}"},
                timeout=120,
                **kwargs,
            )
            self.http_raise_for_status(response)
            return response
        except requests.exceptions.RequestException as exc:
            msg = f"Could not execute GET request to '{url}'."
            if exc.response:
                msg += f" Response content received: '{exc.response.content.decode()}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def http_get(self, url: str, **kwargs: Any) -> requests.Response:
        """Make a paged HTTP GET request and return all values

        Returns:
            requests.Response: The response from the remote server, with all values combined

        Raises:
            DataSafeHavenMicrosoftGraphError if the request failed
        """
        try:
            base_url = url
            values = []

            # Keep requesting new pages until there are no more
            while True:
                response = self.http_get_single_page(url, **kwargs)
                values += response.json()["value"]
                url = response.json().get("@odata.nextLink", None)
                if not url:
                    break

            # Add previous response values into the content bytes
            json_content = response.json()
            json_content["value"] = values
            response._content = json.dumps(json_content).encode("utf-8")

            # Return the full response
            self.http_raise_for_status(response)
            return response
        except requests.exceptions.RequestException as exc:
            msg = f"Could not execute GET request to '{base_url}'."
            if exc.response:
                msg += f" Response content received: '{exc.response.content.decode()}'."
            msg += f" Token {self.token}."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def http_patch(self, url: str, **kwargs: Any) -> requests.Response:
        """Make an HTTP PATCH request

        Returns:
            requests.Response: The response from the remote server

        Raises:
            DataSafeHavenMicrosoftGraphError if the request failed
        """
        try:
            response = requests.patch(
                url,
                headers={"Authorization": f"Bearer {self.token}"},
                timeout=120,
                **kwargs,
            )
            self.http_raise_for_status(response)
            return response
        except requests.exceptions.RequestException as exc:
            msg = f"Could not execute PATCH request to '{url}'."
            if exc.response:
                msg += f" Response content received: '{exc.response.content.decode()}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def http_post(self, url: str, **kwargs: Any) -> requests.Response:
        """Make an HTTP POST request

        Returns:
            requests.Response: The response from the remote server

        Raises:
            DataSafeHavenMicrosoftGraphError if the request failed
        """
        try:
            response = requests.post(
                url,
                headers={"Authorization": f"Bearer {self.token}"},
                timeout=120,
                **kwargs,
            )
            self.http_raise_for_status(response)

            # Wait for operation to complete before returning
            time.sleep(30)
            return response
        except requests.exceptions.RequestException as exc:
            msg = f"Could not execute POST request to '{url}'."
            if exc.response:
                msg += f" Response content received: '{exc.response.content.decode()}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def read_applications(self) -> Sequence[dict[str, Any]]:
        """Get list of applications

        Returns:
            JSON: A JSON list of applications

        Raises:
            DataSafeHavenMicrosoftGraphError if applications could not be loaded
        """
        try:
            return [
                dict(obj)
                for obj in self.http_get(f"{self.base_endpoint}/applications").json()[
                    "value"
                ]
            ]
        except Exception as exc:
            msg = "Could not load list of applications."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def read_application_permissions(
        self, application_service_principal_id: str
    ) -> Sequence[dict[str, Any]]:
        """Get list of application permissions

        Returns:
            JSON: A JSON list of application permissions

        Raises:
            DataSafeHavenMicrosoftGraphError if application permissions could not be loaded
        """
        try:
            delegated = self.http_get(
                f"{self.base_endpoint}/servicePrincipals/{application_service_principal_id}/oauth2PermissionGrants",
            ).json()["value"]
            application = self.http_get(
                f"{self.base_endpoint}/servicePrincipals/{application_service_principal_id}/appRoleAssignments",
            ).json()["value"]
            return [dict(obj) for obj in (delegated + application)]
        except Exception as exc:
            msg = "Could not load list of application permissions."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def read_domains(self) -> Sequence[dict[str, Any]]:
        """Get details of Entra domains

        Returns:
            JSON: A JSON list of Entra domains

        Raises:
            DataSafeHavenMicrosoftGraphError if domains could not be loaded
        """
        try:
            json_response = self.http_get(f"{self.base_endpoint}/domains").json()
            return [dict(obj) for obj in json_response["value"]]
        except Exception as exc:
            msg = "Could not load list of domains."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def read_groups(
        self,
        attributes: Sequence[str] | None = None,
    ) -> Sequence[dict[str, Any]]:
        """Get details of Entra groups

        Returns:
            JSON: A JSON list of Entra ID groups

        Raises:
            DataSafeHavenMicrosoftGraphError if groups could not be loaded
        """
        try:
            endpoint = f"{self.base_endpoint}/groups"
            if attributes:
                endpoint += f"?$select={','.join(attributes)}"
            return [dict(obj) for obj in self.http_get(endpoint).json()["value"]]
        except Exception as exc:
            msg = "Could not load list of groups."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def read_service_principals(self) -> Sequence[dict[str, Any]]:
        """Get list of service principals"""
        try:
            return [
                dict(obj)
                for obj in self.http_get(
                    f"{self.base_endpoint}/servicePrincipals"
                ).json()["value"]
            ]
        except Exception as exc:
            msg = "Could not load list of service principals."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def read_users(
        self, attributes: Sequence[str] | None = None
    ) -> Sequence[dict[str, Any]]:
        """Get details of Entra users

        Returns:
            JSON: A JSON list of Entra users

        Raises:
            DataSafeHavenMicrosoftGraphError if users could not be loaded
        """
        attributes = (
            attributes
            if attributes
            else [
                "accountEnabled",
                "businessPhones",
                "displayName",
                "givenName",
                "id",
                "mail",
                "mailNickname",
                "mobilePhone",
                "onPremisesSamAccountName",
                "onPremisesSyncEnabled",
                "userPrincipalName",
                "surname",
                "telephoneNumber",
                "userPrincipalName",
            ]
        )
        users: Sequence[dict[str, Any]]
        try:
            endpoint = f"{self.base_endpoint}/users"
            if attributes:
                endpoint += f"?$select={','.join(attributes)}"
            users = self.http_get(endpoint).json()["value"]
            administrators = self.http_get(
                f"{self.base_endpoint}/directoryRoles/roleTemplateId="
                f"{self.role_template_ids['Global Administrator']}/members"
            ).json()["value"]
            for user in users:
                user["isGlobalAdmin"] = any(
                    user["id"] == admin["id"] for admin in administrators
                )
            return users
        except Exception as exc:
            msg = "Could not load list of users."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def remove_user(
        self,
        username: str,
    ) -> None:
        """Remove a user from Entra ID

        Raises:
            DataSafeHavenMicrosoftGraphError if the user could not be removed
        """
        try:
            user_id = self.get_id_from_username(username)
            # Attempt to remove user from group
            self.http_delete(
                f"{self.base_endpoint}/users/{user_id}",
            )
            return
        except Exception as exc:
            msg = f"Could not remove user '{username}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def remove_user_from_group(
        self,
        username: str,
        group_name: str,
    ) -> None:
        """Remove a user from an Entra group

        Raises:
            DataSafeHavenMicrosoftGraphError if the user could not be removed
        """
        try:
            user_id = self.get_id_from_username(username)
            group_id = self.validate_entra_group(group_name)
            # Check whether user is in group
            json_response = self.http_get(
                f"{self.base_endpoint}/groups/{group_id}/members",
            ).json()
            # Remove user from group if it is a member
            if user_id in (
                group_member["id"] for group_member in json_response["value"]
            ):
                self.http_delete(
                    f"{self.base_endpoint}/groups/{group_id}/members/{user_id}/$ref",
                )
                self.logger.info(
                    f"Removed [green]'{username}'[/] from group [green]'{group_name}'[/]."
                )
            else:
                self.logger.info(
                    f"User [green]'{username}'[/] does not belong to group [green]'{group_name}'[/]."
                )
        except Exception as exc:
            msg = f"Could not remove user '{username}' from group '{group_name}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def verify_custom_domain(
        self, domain_name: str, expected_nameservers: Sequence[str]
    ) -> None:
        """Verify Entra custom domain

        Raises:
            DataSafeHavenMicrosoftGraphError if domain could not be verified
        """
        try:
            # Check whether the domain has been added to Entra ID
            domains = self.read_domains()
            if not any(d["id"] == domain_name for d in domains):
                msg = f"Domain {domain_name} has not been added to Entra ID."
                raise DataSafeHavenMicrosoftGraphError(msg)
            # Loop until domain delegation is complete
            while True:
                # Check whether all expected nameservers are active
                with suppress(resolver.NXDOMAIN):
                    self.logger.debug(
                        f"Checking [green]{domain_name}[/] domain registration status ..."
                    )
                    active_nameservers = [
                        str(ns) for ns in iter(resolver.resolve(domain_name, "NS"))
                    ]
                    if all(
                        any(nameserver in n for n in active_nameservers)
                        for nameserver in expected_nameservers
                    ):
                        self.logger.info(
                            f"Verified that [green]{domain_name}[/] is registered as a custom Entra ID domain."
                        )
                        break
                self.logger.warning(
                    f"Domain [green]{domain_name}[/] is not currently registered as a custom Entra ID domain."
                )
                # Prompt user to set domain delegation manually
                docs_link = "https://learn.microsoft.com/en-us/azure/dns/dns-delegate-domain-azure-dns#delegate-the-domain"
                self.logger.info(
                    f"To proceed you will need to delegate [green]{domain_name}[/] to Azure ({docs_link})"
                )
                ns_list = ", ".join([f"[green]{n}[/]" for n in expected_nameservers])
                self.logger.info(
                    f"You will need to create NS records pointing to: {ns_list}"
                )
                if not console.confirm(
                    f"Are you ready to check whether [green]{domain_name}[/] has been delegated to Azure?",
                    default_to_yes=True,
                ):
                    self.logger.error("User terminated check for domain delegation.")
                    raise typer.Exit(1)
            # Send verification request if needed
            if not any((d["id"] == domain_name and d["isVerified"]) for d in domains):
                response = self.http_post(
                    f"{self.base_endpoint}/domains/{domain_name}/verify"
                )
                if not response.json()["isVerified"]:
                    raise DataSafeHavenMicrosoftGraphError(response.content)
        except Exception as exc:
            msg = f"Could not verify domain '{domain_name}'."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc
