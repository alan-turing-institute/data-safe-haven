"""Interface to the Microsoft Graph API"""

import datetime
import pathlib
import time
from collections.abc import Sequence
from contextlib import suppress
from io import UnsupportedOperation
from typing import Any, ClassVar

import requests
from dns import resolver
from msal import (
    ConfidentialClientApplication,
    PublicClientApplication,
    SerializableTokenCache,
)

from data_safe_haven.exceptions import (
    DataSafeHavenInputError,
    DataSafeHavenInternalError,
    DataSafeHavenMicrosoftGraphError,
)
from data_safe_haven.utility import LoggingSingleton, NonLoggingSingleton


class LocalTokenCache(SerializableTokenCache):
    def __init__(self, token_cache_filename: pathlib.Path) -> None:
        super().__init__()
        self.token_cache_filename = token_cache_filename
        try:
            if self.token_cache_filename.exists():
                with open(self.token_cache_filename, encoding="utf-8") as f_token:
                    self.deserialize(f_token.read())
        except (FileNotFoundError, UnsupportedOperation):
            self.deserialize(None)

    def __del__(self) -> None:
        with open(self.token_cache_filename, "w", encoding="utf-8") as f_token:
            f_token.write(self.serialize())


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
        tenant_id: str | None = None,
        auth_token: str | None = None,
        application_id: str | None = None,
        application_secret: str | None = None,
        base_endpoint: str = "",
        default_scopes: Sequence[str] = [],
        disable_logging: bool = False,
    ):
        self.base_endpoint = (
            base_endpoint if base_endpoint else "https://graph.microsoft.com/v1.0"
        )
        self.default_scopes = list(default_scopes)
        self.logger = NonLoggingSingleton() if disable_logging else LoggingSingleton()
        self.tenant_id = tenant_id
        if auth_token:
            self.token = auth_token
        elif application_id and application_secret:
            self.token = self.create_token_application(
                application_id, application_secret
            )
        else:
            self.token = self.create_token_administrator()

    def add_custom_domain(self, domain_name: str) -> str:
        """Add AzureAD custom domain

        Returns:
            str: Registration TXT record

        Raises:
            DataSafeHavenMicrosoftGraphError if domain could not be added
        """
        try:
            # Create the AzureAD custom domain if it does not already exist
            domains = self.read_domains()
            domain_exists = any(domain["id"] == domain_name for domain in domains)
            if not domain_exists:
                response = self.http_post(
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
            msg = f"Could not register domain '{domain_name}'.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def add_user_to_group(
        self,
        username: str,
        group_name: str,
    ) -> None:
        """Add a user to a group

        Raises:
            DataSafeHavenMicrosoftGraphError if the token could not be created
        """
        try:
            user_id = self.get_id_from_username(username)
            group_id = self.get_id_from_groupname(group_name)
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
            msg = f"Could not add user '{username}' to group '{group_name}'.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def create_application(
        self,
        application_name: str,
        application_scopes: Sequence[str] = [],
        delegated_scopes: Sequence[str] = [],
        request_json: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Create an AzureAD application if it does not already exist

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

            # Return JSON representation of the AzureAD application
            return json_response
        except Exception as exc:
            msg = f"Could not create application '{application_name}'.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def create_application_secret(
        self, application_name: str, application_secret_name: str
    ) -> str:
        """Add a secret to an existing AzureAD application

        Returns:
            str: Contents of newly-created secret

        Raises:
            DataSafeHavenMicrosoftGraphError if the secret could not be created or already exists
        """
        try:
            application_json = self.get_application_by_name(application_name)
            if not application_json:
                msg = f"Could not retrieve application '{application_name}'"
                raise DataSafeHavenMicrosoftGraphError(msg)
            # If the secret already exists then raise an exception
            if "passwordCredentials" in application_json and any(
                cred["displayName"] == application_secret_name
                for cred in application_json["passwordCredentials"]
            ):
                msg = f"Secret '{application_secret_name}' already exists in application '{application_name}'."
                raise DataSafeHavenInputError(msg)
            # Create the application secret if it does not exist
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
            self.logger.info(
                f"Created application secret '[green]{application_secret_name}[/]'.",
            )
            return str(json_response["secretText"])
        except Exception as exc:
            msg = f"Could not create application secret '{application_secret_name}'.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def create_group(self, group_name: str) -> None:
        """Create an AzureAD group if it does not already exist

        Raises:
            DataSafeHavenMicrosoftGraphError if the group could not be created
        """
        try:
            if self.get_id_from_groupname(group_name):
                self.logger.info(
                    f"Found existing AzureAD group '[green]{group_name}[/]'.",
                )
                return
            self.logger.debug(
                f"Creating AzureAD group '[green]{group_name}[/]'...",
            )
            request_json = {
                "description": group_name,
                "displayName": group_name,
                "groupTypes": [],
                "mailEnabled": False,
                "mailNickname": ("".join(filter(str.isalnum, group_name))).lower(),
                "securityEnabled": True,
            }
            self.http_post(
                f"{self.base_endpoint}/groups",
                json=request_json,
            ).json()
            self.logger.info(
                f"Created AzureAD group '[green]{group_name}[/]'.",
            )
        except Exception as exc:
            msg = f"Could not create AzureAD group '{group_name}'.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def ensure_application_service_principal(
        self, application_name: str
    ) -> dict[str, Any]:
        """Create a service principal for an AzureAD application if it does not already exist

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
            msg = f"Could not create service principal for application '[green]{application_name}[/]'.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def create_token_administrator(self) -> str:
        """Create an access token for a global administrator

        Raises:
            DataSafeHavenMicrosoftGraphError if the token could not be created
        """
        result = None
        try:
            # Load local token cache
            local_token_cache = LocalTokenCache(
                pathlib.Path.home() / f".msal_cache_{self.tenant_id}"
            )
            # Use the Powershell application by default as this should be pre-installed
            app = PublicClientApplication(
                authority=f"https://login.microsoftonline.com/{self.tenant_id}",
                client_id="14d82eec-204b-4c2f-b7e8-296a70dab67e",  # this is the Powershell client id
                token_cache=local_token_cache,
            )
            # Attempt to load token from cache
            if accounts := app.get_accounts():
                result = app.acquire_token_silent(
                    self.default_scopes, account=accounts[0]
                )
            # Initiate device code flow
            if not result:
                flow = app.initiate_device_flow(scopes=self.default_scopes)
                if "user_code" not in flow:
                    msg = f"Could not initiate device login for scopes {self.default_scopes}."
                    raise DataSafeHavenMicrosoftGraphError(msg)
                self.logger.info(
                    "Administrator approval is needed in order to interact with Azure Active Directory."
                )
                self.logger.info(
                    "Please sign-in with [bold]global administrator[/] credentials for"
                    f" Azure Active Directory [green]{self.tenant_id}[/]."
                )
                self.logger.info(
                    "Note that the sign-in screen will prompt you to sign-in to"
                    " [blue]Microsoft Graph Command Line Tools[/] - this is expected."
                )
                self.logger.info(flow["message"])
                # Block until a response is received
                result = app.acquire_token_by_device_flow(flow)
            return str(result["access_token"])
        except Exception as exc:
            error_description = "Could not create Microsoft Graph access token."
            if isinstance(result, dict) and "error_description" in result:
                error_description += f"\n{result['error_description']}."
            msg = f"{error_description}\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def create_token_application(
        self, application_id: str, application_secret: str
    ) -> str:
        """Return an access token for the given application ID and secret

        Raises:
            DataSafeHavenMicrosoftGraphError if the token could not be created
        """
        result = None
        try:
            # Use a created application
            app = ConfidentialClientApplication(
                client_id=application_id,
                client_credential=application_secret,
                authority=f"https://login.microsoftonline.com/{self.tenant_id}",
            )
            # Block until a response is received
            # For this call the scopes are pre-defined by the application privileges
            result = app.acquire_token_for_client(
                scopes=["https://graph.microsoft.com/.default"]
            )
            if not isinstance(result, dict):
                msg = "Invalid application token returned from Microsoft Graph."
                raise DataSafeHavenMicrosoftGraphError(msg)
            return str(result["access_token"])
        except Exception as exc:
            error_description = "Could not create access token"
            if result and "error_description" in result:
                error_description += f": {result['error_description']}"
            msg = f"{error_description}.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def create_user(
        self,
        request_json: dict[str, Any],
        email_address: str,
        phone_number: str,
    ) -> None:
        """Create an AzureAD user if it does not already exist

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
                    f"Updating AzureAD user '[green]{username}[/]'...",
                )
                final_verb = "Update"
            else:
                self.logger.debug(
                    f"Creating AzureAD user '[green]{username}[/]'...",
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
                self.http_post(
                    f"https://graph.microsoft.com/beta/users/{user_id}/authentication/emailMethods",
                    json={"emailAddress": email_address},
                )
            except DataSafeHavenMicrosoftGraphError as exc:
                if "already registered" not in str(exc):
                    msg = f"Failed to add authentication email address '{email_address}'.\n{exc}"
                    raise DataSafeHavenMicrosoftGraphError(msg) from exc
            # Set the authentication phone number
            try:
                self.http_post(
                    f"https://graph.microsoft.com/beta/users/{user_id}/authentication/phoneMethods",
                    json={"phoneNumber": phone_number, "phoneType": "mobile"},
                )
            except DataSafeHavenMicrosoftGraphError as exc:
                if "already registered" not in str(exc):
                    msg = f"Failed to add authentication phone number '{phone_number}'.\n{exc}"
                    raise DataSafeHavenMicrosoftGraphError(msg) from exc
            # Ensure user is enabled
            self.http_patch(
                f"{self.base_endpoint}/users/{user_id}",
                json={"accountEnabled": True},
            )
            self.logger.info(
                f"{final_verb}d AzureAD user '[green]{username}[/]'.",
            )
        except DataSafeHavenMicrosoftGraphError as exc:
            msg = f"Could not {final_verb.lower()} user {username}.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def delete_application(
        self,
        application_name: str,
    ) -> None:
        """Remove an application from AzureAD

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
            msg = f"Could not delete application '{application_name}'.\n{exc}"
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

    def get_id_from_application_name(self, application_name: str) -> str | None:
        try:
            application = self.get_application_by_name(application_name)
            if not application:
                return None
            return str(application["appId"])
        except DataSafeHavenMicrosoftGraphError:
            return None

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
            msg = f"Could not assign application role '{application_role_name}' to application '{application_name}'.\n{exc}"
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
            msg = f"Could not assign delegated role '{application_role_name}' to application '{application_name}'.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

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
            # We do not use response.ok as this allows 3xx codes
            if (
                requests.codes.OK
                <= response.status_code
                < requests.codes.MULTIPLE_CHOICES
            ):
                return response
            raise DataSafeHavenInternalError(response.content)
        except Exception as exc:
            msg = f"Could not execute DELETE request to '{url}'.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def http_get(self, url: str, **kwargs: Any) -> requests.Response:
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
            # We do not use response.ok as this allows 3xx codes
            if (
                requests.codes.OK
                <= response.status_code
                < requests.codes.MULTIPLE_CHOICES
            ):
                return response
            raise DataSafeHavenInternalError(response.content)
        except Exception as exc:
            msg = f"Could not execute GET request from '{url}'.\n{exc}"
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
            # We do not use response.ok as this allows 3xx codes
            if (
                requests.codes.OK
                <= response.status_code
                < requests.codes.MULTIPLE_CHOICES
            ):
                return response
            raise DataSafeHavenInternalError(response.content)
        except Exception as exc:
            msg = f"Could not execute PATCH request to '{url}'.\n{exc}"
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
            # We do not use response.ok as this allows 3xx codes
            if (
                requests.codes.OK
                <= response.status_code
                < requests.codes.MULTIPLE_CHOICES
            ):
                time.sleep(30)  # wait for operation to complete
                return response
            raise DataSafeHavenInternalError(response.content)
        except Exception as exc:
            msg = f"Could not execute POST request to '{url}'.\n{exc}"
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
            msg = f"Could not load list of applications.\n{exc}"
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
            msg = f"Could not load list of application permissions.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def read_domains(self) -> Sequence[dict[str, Any]]:
        """Get details of AzureAD domains

        Returns:
            JSON: A JSON list of AzureAD domains

        Raises:
            DataSafeHavenMicrosoftGraphError if domains could not be loaded
        """
        try:
            json_response = self.http_get(f"{self.base_endpoint}/domains").json()
            return [dict(obj) for obj in json_response["value"]]
        except Exception as exc:
            msg = f"Could not load list of domains.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def read_groups(
        self,
        attributes: Sequence[str] | None = None,
    ) -> Sequence[dict[str, Any]]:
        """Get details of AzureAD groups

        Returns:
            JSON: A JSON list of AzureAD groups

        Raises:
            DataSafeHavenMicrosoftGraphError if groups could not be loaded
        """
        try:
            endpoint = f"{self.base_endpoint}/groups"
            if attributes:
                endpoint += f"?$select={','.join(attributes)}"
            return [dict(obj) for obj in self.http_get(endpoint).json()["value"]]
        except Exception as exc:
            msg = f"Could not load list of groups.\n{exc}"
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
            msg = f"Could not load list of service principals.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def read_users(
        self, attributes: Sequence[str] | None = None
    ) -> Sequence[dict[str, Any]]:
        """Get details of AzureAD users

        Returns:
            JSON: A JSON list of AzureAD users

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
            msg = f"Could not load list of users.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def remove_user(
        self,
        username: str,
    ) -> None:
        """Remove a user from AzureAD

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
            msg = f"Could not remove user '{username}'.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def remove_user_from_group(
        self,
        username: str,
        group_name: str,
    ) -> None:
        """Remove a user from an AzureAD group

        Raises:
            DataSafeHavenMicrosoftGraphError if the user could not be removed
        """
        try:
            user_id = self.get_id_from_username(username)
            group_id = self.get_id_from_groupname(group_name)
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
            msg = (
                f"Could not remove user '{username}' from group '{group_name}'.\n{exc}"
            )
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def verify_custom_domain(
        self, domain_name: str, expected_nameservers: Sequence[str]
    ) -> None:
        """Verify AzureAD custom domain

        Raises:
            DataSafeHavenMicrosoftGraphError if domain could not be verified
        """
        try:
            # Create the AzureAD custom domain if it does not already exist
            domains = self.read_domains()
            if not any(d["id"] == domain_name for d in domains):
                msg = f"Domain {domain_name} has not been added to AzureAD."
                raise DataSafeHavenMicrosoftGraphError(msg)
            # Wait until domain delegation is complete
            while True:
                # Check whether all expected nameservers are active
                with suppress(resolver.NXDOMAIN):
                    self.logger.info(
                        f"Checking [green]{domain_name}[/] domain verification status ..."
                    )
                    active_nameservers = [
                        str(ns) for ns in iter(resolver.resolve(domain_name, "NS"))
                    ]
                    if all(
                        any(nameserver in n for n in active_nameservers)
                        for nameserver in expected_nameservers
                    ):
                        self.logger.info(
                            f"Verified that domain [green]{domain_name}[/] is delegated to Azure."
                        )
                        break
                self.logger.warning(
                    f"Domain [green]{domain_name}[/] is not currently delegated to Azure."
                )
                # Prompt user to set domain delegation manually
                docs_link = "https://learn.microsoft.com/en-us/azure/dns/dns-delegate-domain-azure-dns#delegate-the-domain"
                self.logger.info(
                    f"To proceed you will need to delegate [green]{domain_name}[/] to Azure ({docs_link})"
                )
                ns_list = ", ".join([f"[green]{n}[/]" for n in expected_nameservers])
                self.logger.info(
                    f"You will need to create an NS record pointing to: {ns_list}"
                )
                if isinstance(self.logger, LoggingSingleton):
                    self.logger.confirm(
                        f"Are you ready to check whether [green]{domain_name}[/] has been delegated to Azure?",
                        default_to_yes=True,
                    )
                else:
                    msg = "Unable to confirm Azure nameserver delegation."
                    raise NotImplementedError(msg)
            # Send verification request if needed
            if not any((d["id"] == domain_name and d["isVerified"]) for d in domains):
                response = self.http_post(
                    f"{self.base_endpoint}/domains/{domain_name}/verify"
                )
                if not response.json()["isVerified"]:
                    raise DataSafeHavenMicrosoftGraphError(response.content)
        except Exception as exc:
            msg = f"Could not verify domain '{domain_name}'.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc
