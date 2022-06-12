"""Interface to the Microsoft Graph API"""
# Standard library imports
import datetime
import json
import requests
import time
from typing import Any, Sequence

# Third party imports
from msal import ConfidentialClientApplication, PublicClientApplication

# Local imports
from data_safe_haven.exceptions import (
    DataSafeHavenInputException,
    DataSafeHavenInternalException,
    DataSafeHavenMicrosoftGraphException,
)
from data_safe_haven.mixins import LoggingMixin
from .types import JSONType


class GraphApi(LoggingMixin):
    linux_schema = "extj8xolrvw_linux"  # this is the "Extension with Properties for Linux User and Groups" extension
    role_template_ids = {"Global Administrator": "62e90394-69f5-4237-9190-012177145e10"}
    uuid_application = {
        "Directory.Read.All": "7ab1d382-f21e-4acd-a863-ba3e13f7da61",
        "Domain.Read.All": "dbb9058a-0e50-45d7-ae91-66909b5d4664",
        "Group.Read.All": "5b567255-7703-4780-807c-7be8301ae99b",
        "Group.ReadWrite.All": "62a82d76-70ea-41e2-9197-370581804d09",
        "User.Read.All": "df021288-bdef-4463-88db-98f22de89214",
        "User.ReadWrite.All": "741f803b-c850-494e-b5df-cde7c675a1ca",
        "UserAuthenticationMethod.ReadWrite.All": "50483e42-d915-4231-9639-7fdb7fd190e5",
    }
    uuid_delegated = {
        "GroupMember.Read.All": "bc024368-1153-4739-b217-4326f2e966d0",
        "User.Read.All": "a154be20-db9c-4678-8ab7-66f6cc099a59",
    }

    def __init__(
        self,
        tenant_id: str,
        auth_token: str = None,
        application_id: str = None,
        application_secret: str = None,
        base_endpoint: str = "",
        default_scopes: Sequence[str] = [],
        *args: Any,
        **kwargs: Any,
    ):
        super().__init__(*args, **kwargs)

        self.tenant_id = tenant_id
        self.base_endpoint = (
            base_endpoint if base_endpoint else "https://graph.microsoft.com/v1.0"
        )
        self.default_scopes = default_scopes
        if auth_token:
            self.token = auth_token
        elif application_id and application_secret:
            self.token = self.create_token_application(
                application_id, application_secret
            )
        else:
            self.token = self.create_token_administrator()

    def add_user_to_group(
        self,
        username: str,
        group_name: str,
    ) -> None:
        """Add a user to a group

        Raises:
            DataSafeHavenMicrosoftGraphException if the token could not be created
        """
        try:
            user_id = self.get_id_from_username(username)
            group_id = self.get_id_from_groupname(group_name)
            json_response = self.http_get(
                f"{self.base_endpoint}/groups/{group_id}/members",
            ).json()
            # If user already belongs to group then do nothing further
            if any([user_id == member["id"] for member in json_response["value"]]):
                self.info(
                    f"User <fg=green>'{username}'</> is already a member of group <fg=green>'{group_name}'</>."
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
                self.info(f"Added user <fg=green>'{username}'</> to group <fg=green>'{group_name}'</>.")
        except (DataSafeHavenMicrosoftGraphException, IndexError) as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not add user '{username}' to group '{group_name}'.\n{str(exc)}"
            ) from exc

    def create_application(
        self,
        application_name: str,
        application_scopes: Sequence[str] = [],
        delegated_scopes: Sequence[str] = [],
        request_json: JSONType = None,
    ) -> None:
        """Create an AzureAD application if it does not already exist

        Raises:
            DataSafeHavenMicrosoftGraphException if the application could not be created
        """
        try:
            # Check for an existing application
            if self.get_application_by_name(application_name):
                self.info(
                    f"Application '<fg=green>{application_name}</>' already exists."
                )
            else:
                # Create a new application
                self.info(
                    f"Creating new application '<fg=green>{application_name}</>'...",
                    no_newline=True,
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
                            "resourceAppId": "00000003-0000-0000-c000-000000000000",  # Microsoft Graph: https://graph.microsoft.com
                            "resourceAccess": scopes,
                        }
                    ]
                json_response = self.http_post(
                    f"{self.base_endpoint}/applications",
                    json=request_json,
                ).json()
                self.info(
                    f"Created new application '<fg=green>{json_response['displayName']}</>'.",
                    overwrite=True,
                )

            # Grant admin consent for the requested scopes
            if application_scopes or delegated_scopes:
                application_id = self.get_id_from_application_name(application_name)
                application_sp = self.get_service_principal_by_name(application_name)
                if not (
                    application_sp
                    and self.read_application_permissions(application_sp["id"])
                ):
                    self.info(
                        f"Application <fg=green>{application_name}</> has requested permissions that need administrator approval."
                    )
                    self.info(
                        "Please sign-in with <fg=green>global administrator</> credentials for the Azure Active Directory where your users are stored."
                    )
                    self.info(
                        f"To sign in, use a web browser to open the page <fg=green>https://login.microsoftonline.com/{self.tenant_id}/adminconsent?client_id={application_id}&redirect_uri=https://login.microsoftonline.com/common/oauth2/nativeclient</> and follow the instructions."
                    )
                    while True:
                        if application_sp := self.get_service_principal_by_name(
                            application_name
                        ):
                            if self.read_application_permissions(application_sp["id"]):
                                break
                        time.sleep(10)
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not create application '{application_name}'.\n{str(exc)}"
            ) from exc

    def create_application_secret(
        self, application_secret_name: str, application_name: str
    ) -> str:
        """Add a secret to an existing AzureAD application

        Returns:
            str: Contents of newly-created secret

        Raises:
            DataSafeHavenMicrosoftGraphException if the secret could not be created or already exists
        """
        try:
            application_json = self.get_application_by_name(application_name)
            # If the secret already exists then raise an exception
            if "passwordCredentials" in application_json and any(
                [
                    cred["displayName"] == application_secret_name
                    for cred in application_json["passwordCredentials"]
                ]
            ):
                raise DataSafeHavenInputException(
                    f"Secret '{application_secret_name}' already exists in application '{application_name}'."
                )
            # Create the application secret if it does not exist
            self.info(
                f"Creating application secret '<fg=green>{application_secret_name}</>'...",
                no_newline=True,
            )
            request_json = {
                "passwordCredential": {
                    "displayName": application_secret_name,
                    "endDateTime": (
                        datetime.datetime.now(datetime.timezone.utc)
                        + datetime.timedelta(weeks=520)
                    ).strftime("%Y-%m-%dT%H:%M:%SZ"),
                }
            }
            json_response = self.http_post(
                f"{self.base_endpoint}/applications/{application_json['id']}/addPassword",
                json=request_json,
            ).json()
            self.info(
                f"Created application secret '<fg=green>{application_secret_name}</>'.",
                overwrite=True,
            )
            return json_response["secretText"]
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not create application secret '{application_secret_name}'.\n{str(exc)}"
            ) from exc

    def create_group(
        self, group_name: str, group_id: str, verbose: bool = True
    ) -> None:
        """Create an AzureAD group if it does not already exist

        Raises:
            DataSafeHavenMicrosoftGraphException if the group could not be created
        """
        try:
            if self.get_id_from_groupname(group_name):
                if verbose:
                    self.info(
                        f"Found existing AzureAD group '<fg=green>{group_name}</>'.",
                    )
                return
            if verbose:
                self.info(
                    f"Creating AzureAD group '<fg=green>{group_name}</>'...",
                    no_newline=True,
                )
            endpoint = f"{self.base_endpoint}/groups"
            request_json = {
                "displayName": group_name,
                "groupTypes": [],
                "mailEnabled": False,
                "mailNickname": group_name,
                "securityEnabled": True,
            }
            json_response = self.http_post(
                endpoint,
                json=request_json,
            ).json()
            # Add Linux group name and ID
            patch_json = {
                self.linux_schema: {
                    "group": group_name,
                    "gid": group_id,
                }
            }
            self.http_patch(
                f"{self.base_endpoint}/groups/{json_response['id']}",
                json=patch_json,
            )
            if verbose:
                self.info(
                    f"Created AzureAD group '<fg=green>{group_name}</>'.",
                    overwrite=True,
                )
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not create AzureAD group '{group_name}'.\n{str(exc)}"
            ) from exc

    def create_token_administrator(self) -> str:
        """Create an access token for a global administrator

        Raises:
            DataSafeHavenMicrosoftGraphException if the token could not be created
        """
        try:
            # Use the default application
            app = PublicClientApplication(
                client_id="14d82eec-204b-4c2f-b7e8-296a70dab67e",  # this is the Powershell client id
                # client_id="04b07795-8ddb-461a-bbee-02f9e1bf7b46",  # this is the Azure CLI client id
                authority=f"https://login.microsoftonline.com/{self.tenant_id}",
            )
            # Initiate device code flow
            flow = app.initiate_device_flow(scopes=self.default_scopes)
            if "user_code" not in flow:
                raise DataSafeHavenMicrosoftGraphException(
                    f"Could not initiate device login for scopes {self.default_scopes}."
                )
            self.info(
                f"Making changes to Azure Active Directory needs administrator approval."
            )
            self.info(
                "Please sign-in with <fg=green>global administrator</> credentials for the Azure Active Directory where your users are stored."
            )
            self.info(
                "Note that the sign-in screen will prompt you to sign-in to <fg=blue>Microsoft Graph Powershell</> - this is expected."
            )
            self.info(flow["message"])
            # Block until a response is received
            result = app.acquire_token_by_device_flow(flow)
            return result["access_token"]
        except Exception as exc:
            error_description = f"Could not create access token"
            if result and "error_description" in result:
                error_description += f": {result['error_description']}"
            raise DataSafeHavenMicrosoftGraphException(f"{error_description}.\n{str(exc)}") from exc

    def create_token_application(
        self, application_id: str, application_secret: str
    ) -> str:
        """Return an access token for the given application ID and secret

        Raises:
            DataSafeHavenMicrosoftGraphException if the token could not be created
        """
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
                scopes="https://graph.microsoft.com/.default"
            )
            return result["access_token"]
        except Exception as exc:
            error_description = f"Could not create access token"
            if result and "error_description" in result:
                error_description += f": {result['error_description']}"
            raise DataSafeHavenMicrosoftGraphException(f"{error_description}.\n{str(exc)}") from exc

    def create_user(
        self,
        request_json: JSONType,
        email_address: str,
        phone_number: str,
    ) -> None:
        """Create an AzureAD user if it does not already exist

        Raises:
            DataSafeHavenMicrosoftGraphException if the user could not be created
        """
        username = request_json["mailNickname"]
        try:
            # Check whether user already exists
            user_id = self.get_id_from_username(username)
            final_verb = ""
            if user_id:
                self.info(
                    f"Updating AzureAD user '<fg=green>{username}</>'...",
                    no_newline=True,
                )
                final_verb = "Updated"
            else:
                self.info(
                    f"Creating AzureAD user '<fg=green>{username}</>'...",
                    no_newline=True,
                )
                final_verb = "Created"
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
            except DataSafeHavenMicrosoftGraphException as exc:
                if "already exists" not in str(exc):
                    raise
            # Set the authentication phone number
            try:
                self.http_post(
                    f"https://graph.microsoft.com/beta/users/{user_id}/authentication/phoneMethods",
                    json={"phoneNumber": phone_number, "phoneType": "mobile"},
                )
            except DataSafeHavenMicrosoftGraphException as exc:
                if "already exists" not in str(exc):
                    raise
            # Ensure user is enabled
            self.http_patch(
                f"{self.base_endpoint}/users/{user_id}",
                json={"accountEnabled": True},
            )
            self.info(
                f"{final_verb} AzureAD user '<fg=green>{username}</>'.",
                overwrite=True,
            )
        except (DataSafeHavenMicrosoftGraphException, IndexError) as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not create/update user {username}.\n{str(exc)}"
            ) from exc

    def delete_application(
        self,
        application_name: str,
    ) -> None:
        """Remove an application from AzureAD

        Raises:
            DataSafeHavenMicrosoftGraphException if the application could not be deleted
        """
        try:
            # Check that the application exists
            application_oid = self.get_application_by_name(application_name)["id"]
            if application_oid:
                # Delete the application
                self.info(
                    f"Deleting application '<fg=green>{application_name}</>'...",
                    no_newline=True,
                )
                self.http_delete(
                    f"{self.base_endpoint}/applications/{application_oid}",
                )
                self.info(
                    f"Deleted application '<fg=green>{application_name}</>'.",
                    overwrite=True,
                )
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not delete application '{application_name}'.\n{str(exc)}"
            ) from exc

    def get_application_by_name(self, application_name: str) -> JSONType:
        try:
            return [
                application
                for application in self.read_applications()
                if application["displayName"] == application_name
            ][0]
        except (DataSafeHavenMicrosoftGraphException, IndexError):
            return None

    def get_service_principal_by_name(self, service_principal_name: str) -> JSONType:
        try:
            return [
                service_principal
                for service_principal in self.read_service_principals()
                if service_principal["displayName"] == service_principal_name
            ][0]
        except (DataSafeHavenMicrosoftGraphException, IndexError):
            return None

    def get_id_from_application_name(self, application_name: str) -> str:
        try:
            return self.get_application_by_name(application_name)["appId"]
        except DataSafeHavenMicrosoftGraphException:
            return None

    def get_id_from_groupname(self, group_name: str) -> str:
        try:
            return [
                group
                for group in self.read_groups()
                if group["displayName"] == group_name
            ][0]["id"]
        except (DataSafeHavenMicrosoftGraphException, IndexError):
            return None

    def get_id_from_username(self, username: str) -> str:
        try:
            return [
                user for user in self.read_users() if user["mailNickname"] == username
            ][0]["id"]
        except (DataSafeHavenMicrosoftGraphException, IndexError):
            return None

    def http_delete(self, url: str, **kwargs: Any) -> requests.Response:
        """Make an HTTP DELETE request

        Returns:
            requests.Response: The response from the remote server

        Raises:
            DataSafeHavenMicrosoftGraphException if the request failed
        """
        try:
            response = requests.delete(
                url, headers={"Authorization": f"Bearer {self.token}"}, **kwargs
            )
            if not response.ok:
                raise DataSafeHavenInternalException(response.content)
            return response
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not execute DELETE request.\n{str(exc)}"
            )

    def http_get(self, url: str, **kwargs: Any) -> requests.Response:
        """Make an HTTP GET request

        Returns:
            requests.Response: The response from the remote server

        Raises:
            DataSafeHavenMicrosoftGraphException if the request failed
        """
        try:
            response = requests.get(
                url, headers={"Authorization": f"Bearer {self.token}"}, **kwargs
            )
            if not response.ok:
                raise DataSafeHavenInternalException(response.content)
            return response
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not execute GET request.\n{str(exc)}"
            )

    def http_patch(self, url: str, **kwargs: Any) -> requests.Response:
        """Make an HTTP PATCH request

        Returns:
            requests.Response: The response from the remote server

        Raises:
            DataSafeHavenMicrosoftGraphException if the request failed
        """
        try:
            response = requests.patch(
                url, headers={"Authorization": f"Bearer {self.token}"}, **kwargs
            )
            if not response.ok:
                raise DataSafeHavenInternalException(response.content)
            return response
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not execute PATCH request.\n{str(exc)}"
            )

    def http_post(self, url: str, **kwargs: Any) -> requests.Response:
        """Make an HTTP POST request

        Returns:
            requests.Response: The response from the remote server

        Raises:
            DataSafeHavenMicrosoftGraphException if the request failed
        """
        try:
            response = requests.post(
                url, headers={"Authorization": f"Bearer {self.token}"}, **kwargs
            )
            if not response.ok:
                raise DataSafeHavenInternalException(response.content)
            time.sleep(30)  # wait for operation to complete
            return response
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not execute POST request.\n{str(exc)}"
            ) from exc

    def read_applications(self) -> JSONType:
        """Get list of applications

        Returns:
            JSON: A JSON list of applications

        Raises:
            DataSafeHavenMicrosoftGraphException if applications could not be loaded

        """
        try:
            return self.http_get(
                f"{self.base_endpoint}/applications",
            ).json()["value"]
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not load list of applications.\n{str(exc)}"
            ) from exc

    def read_application_permissions(
        self, application_service_principal_id: str
    ) -> JSONType:
        """Get list of application permissions

        Returns:
            JSON: A JSON list of application permissions

        Raises:
            DataSafeHavenMicrosoftGraphException if application permissions could not be loaded
        """
        try:
            delegated = self.http_get(
                f"{self.base_endpoint}/servicePrincipals/{application_service_principal_id}/oauth2PermissionGrants",
            ).json()["value"]
            application = self.http_get(
                f"{self.base_endpoint}/servicePrincipals/{application_service_principal_id}/appRoleAssignments",
            ).json()["value"]
            return delegated + application
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not load list of application permissions.\n{str(exc)}"
            ) from exc

    def read_domains(self) -> JSONType:
        """Get details of AzureAD domains

        Returns:
            JSON: A JSON list of AzureAD domains

        Raises:
            DataSafeHavenMicrosoftGraphException if domains could not be loaded
        """
        try:
            json_response = self.http_get(f"{self.base_endpoint}/domains").json()
            return json_response["value"]
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not load list of domains.\n{str(exc)}"
            ) from exc

    def read_groups(
        self,
        attributes: Sequence[str] = None,
    ) -> JSONType:
        """Get details of AzureAD groups

        Returns:
            JSON: A JSON list of AzureAD groups

        Raises:
            DataSafeHavenMicrosoftGraphException if groups could not be loaded
        """
        try:
            endpoint = f"{self.base_endpoint}/groups"
            if attributes:
                endpoint += f"?$select={','.join(attributes)}"
            return self.http_get(endpoint).json()["value"]
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not load list of groups.\n{str(exc)}"
            ) from exc

    def read_service_principals(self) -> JSONType:
        """Get list of service principals"""
        try:
            return self.http_get(
                f"{self.base_endpoint}/servicePrincipals",
            ).json()["value"]
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not load list of service principals.\n{str(exc)}"
            ) from exc

    def read_users(self, attributes: Sequence[str] = None) -> JSONType:
        """Get details of AzureAD users

        Returns:
            JSON: A JSON list of AzureAD users

        Raises:
            DataSafeHavenMicrosoftGraphException if users could not be loaded
        """
        attributes = (
            attributes
            if attributes
            else [
                "accountEnabled",
                "displayName",
                "givenName",
                "id",
                "mail",
                "mailNickname",
                "mobilePhone",
                "userPrincipalName",
                "surname",
                "telephoneNumber",
                "userPrincipalName",
                self.linux_schema,
            ]
        )
        try:
            endpoint = f"{self.base_endpoint}/users"
            if attributes:
                endpoint += f"?$select={','.join(attributes)}"
            users = self.http_get(endpoint).json()["value"]
            administrators = self.http_get(
                f"{self.base_endpoint}/directoryRoles/roleTemplateId={self.role_template_ids['Global Administrator']}/members"
            ).json()["value"]
            for user in users:
                user["isGlobalAdmin"] = any(
                    [user["id"] == admin["id"] for admin in administrators]
                )
                for key, value in user.get(self.linux_schema, {}).items():
                    user[key] = value
                user[self.linux_schema] = {}
            return users
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not load list of users.\n{str(exc)}"
            ) from exc

    def remove_user_from_group(
        self,
        username: str,
        group_name: str,
    ) -> None:
        """Remove a user from an AzureAD group

        Raises:
            DataSafeHavenMicrosoftGraphException if the user could not be removed
        """
        try:
            user_id = self.get_id_from_username(username)
            group_id = self.get_id_from_groupname(group_name)
            # Attempt to remove user from group
            self.http_delete(
                f"{self.base_endpoint}/groups/{group_id}/members/{user_id}/$ref",
            )
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not remove user '{username}' from group '{group_name}'.\n{str(exc)}"
            ) from exc
