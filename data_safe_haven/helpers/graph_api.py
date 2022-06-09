"""Interface to the Microsoft Graph API"""
# Standard library imports
import datetime
import requests
import time


# Third party imports
from msal import ConfidentialClientApplication, PublicClientApplication

# Local imports
from data_safe_haven.exceptions import (
    DataSafeHavenInputException,
    DataSafeHavenMicrosoftGraphException,
)
from data_safe_haven.mixins import LoggingMixin


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

    def __init__(self, tenant_id, base_endpoint="", default_scopes=[], *args, **kwargs):
        super().__init__(*args, **kwargs)

        self.tenant_id = tenant_id
        self.base_endpoint = (
            base_endpoint if base_endpoint else "https://graph.microsoft.com/v1.0"
        )
        self.default_token_ = None
        self.default_scopes = default_scopes

    @property
    def default_token(self):
        if not self.default_token_:
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
                    "Could not initiate device login"
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

            try:
                self.default_token_ = result["access_token"]
            except KeyError:
                raise DataSafeHavenMicrosoftGraphException(
                    f"Could not acquire access token: {result['error_description']}"
                    if result and "error_description" in result
                    else "Could not acquire access token"
                )
        return self.default_token_

    def access_token(self, application_id, application_secret):
        """Return an access token for the given application ID and secret"""
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
        try:
            return result["access_token"]
        except KeyError:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not acquire access token: {result['error_description']}"
                if result and "error_description" in result
                else "Could not acquire access token"
            )

    def add_user_to_group(
        self,
        username,
        group_name,
        auth_token=None,
    ):
        """Create a user if it does not already exist"""
        auth_token = auth_token if auth_token else self.default_token
        try:
            user_id = self.get_id_from_username(username, auth_token)
            group_id = self.get_id_from_groupname(group_name, auth_token)
            # Check whether user already belongs to group
            json_response = self.http_get(
                f"{self.base_endpoint}/groups/{group_id}/members",
                headers={"Authorization": f"Bearer {auth_token}"},
            ).json()
            if any([user_id == member["id"] for member in json_response["value"]]):
                return False
            # Add user to group
            request_json = {
                "@odata.id": f"https://graph.microsoft.com/v1.0/directoryObjects/{user_id}"
            }
            self.http_post(
                f"{self.base_endpoint}/groups/{group_id}/members/$ref",
                headers={"Authorization": f"Bearer {auth_token}"},
                json=request_json,
            )
            self.info(f"Added user '{username}' to group '{group_name}'.")
            return True
        except (DataSafeHavenMicrosoftGraphException, IndexError) as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not create application: {str(exc)}"
            ) from exc

    def application(
        self,
        application_name,
        auth_token=None,
        application_scopes=[],
        delegated_scopes=[],
        request_json=None,
    ):
        """Ensure that an application exists"""
        auth_token = auth_token if auth_token else self.default_token
        # Check for an existing application
        existing_applications = [
            app
            for app in self.list_applications(auth_token)
            if app["displayName"] == application_name
        ]
        if existing_applications:
            return existing_applications[0]

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
        try:
            json_response = self.http_post(
                f"{self.base_endpoint}/applications",
                headers={"Authorization": f"Bearer {auth_token}"},
                json=request_json,
            ).json()
        except DataSafeHavenMicrosoftGraphException as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not create application: {str(exc)}"
            ) from exc
        self.info(
            f"Created new application '<fg=green>{json_response['displayName']}</>'.",
            overwrite=True,
        )

        # Grant admin consent for the requested scopes
        if scopes:
            self.info(
                f"Application <fg=green>{application_name}</> has requested permissions that need administrator approval."
            )
            self.info(
                "Please sign-in with <fg=green>global administrator</> credentials for the Azure Active Directory where your users are stored."
            )
            self.info(
                f"To sign in, use a web browser to open the page <fg=green>https://login.microsoftonline.com/{self.tenant_id}/adminconsent?client_id={json_response['appId']}&redirect_uri=https://login.microsoftonline.com/common/oauth2/nativeclient</> and follow the instructions."
            )
            if not self.log_confirm(
                "Have you consented to the required application permissions?",
                False,
            ):
                raise DataSafeHavenInputException("Admin consent not confirmed")
        return json_response

    def application_secret(
        self, application_secret_name, application_json, auth_token=None
    ):
        auth_token = auth_token if auth_token else self.default_token
        # If the secret already exists then raise an exception
        if "passwordCredentials" in application_json and any(
            [
                cred["displayName"] == application_secret_name
                for cred in application_json["passwordCredentials"]
            ]
        ):
            raise DataSafeHavenMicrosoftGraphException(
                f"Secret '{application_secret_name}' already exists in application '{application_json['displayName']}'."
            )

        # Create the application secret if it does not exist
        try:
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
                headers={"Authorization": f"Bearer {auth_token}"},
                json=request_json,
            ).json()
        except DataSafeHavenMicrosoftGraphException as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not create application secret: {str(exc)}"
            ) from exc
        return json_response["secretText"]

    def create_group(
        self,
        group_name,
        group_id,
        auth_token=None,
    ):
        """Ensure that a group exists. Returns 'True' if new group was created and 'False' if the group already exists."""
        auth_token = auth_token if auth_token else self.default_token
        try:
            if self.get_id_from_groupname(group_name, auth_token):
                return False
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
                headers={"Authorization": f"Bearer {auth_token}"},
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
                headers={"Authorization": f"Bearer {auth_token}"},
                json=patch_json,
            )
            return True
        except DataSafeHavenMicrosoftGraphException as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not create group {group_name}: {str(exc)}"
            ) from exc

    def create_user(
        self,
        request_json,
        email_address,
        phone_number,
        auth_token=None,
    ):
        """Create a user if it does not already exist. Returns 'True' if new user was created and 'False' if the user already exists."""
        auth_token = auth_token if auth_token else self.default_token
        username = request_json["mailNickname"]
        user_was_created = False
        try:
            # Check whether user already exists
            user_id = self.get_id_from_username(username, auth_token)
            if not user_id:
                # If they do not then create them
                endpoint = f"{self.base_endpoint}/users"
                json_response = self.http_post(
                    endpoint,
                    headers={"Authorization": f"Bearer {auth_token}"},
                    json=request_json,
                ).json()
                user_id = json_response["id"]
                user_was_created = True
            # Set the authentication email address
            try:
                self.http_post(
                    f"https://graph.microsoft.com/beta/users/{user_id}/authentication/emailMethods",
                    headers={"Authorization": f"Bearer {auth_token}"},
                    json={"emailAddress": email_address},
                )
            except DataSafeHavenMicrosoftGraphException as exc:
                if "already exists" not in str(exc):
                    raise
            # Set the authentication phone number
            try:
                self.http_post(
                    f"https://graph.microsoft.com/beta/users/{user_id}/authentication/phoneMethods",
                    headers={"Authorization": f"Bearer {auth_token}"},
                    json={"phoneNumber": phone_number, "phoneType": "mobile"},
                )
            except DataSafeHavenMicrosoftGraphException as exc:
                if "already exists" not in str(exc):
                    raise
            # Ensure user is enabled
            self.http_patch(
                f"{self.base_endpoint}/users/{user_id}",
                headers={"Authorization": f"Bearer {auth_token}"},
                json={"accountEnabled": True},
            )
            # Return 'True' if new user was created and 'False' if the user already exists
            return user_was_created
        except (DataSafeHavenMicrosoftGraphException, IndexError) as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not create user {username}: {str(exc)}"
            ) from exc

    def create_user_with_group(
        self,
        request_json,
        email_address,
        phone_number,
        auth_token=None,
    ):
        try:
            # Ensure that the user exists
            self.create_user(request_json, email_address, phone_number, auth_token)
            user = [
                user
                for user in self.get_users(auth_token=auth_token)
                if user["mailNickname"] == request_json["mailNickname"]
            ][0]
            # Create a group with the same name and UID as the user and add the user to it
            self.create_group(user["user"], user["uid"], auth_token)
            self.add_user_to_group(user["user"], user["user"], auth_token)
        except (DataSafeHavenMicrosoftGraphException, IndexError) as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not create user and group: {str(exc)}"
            ) from exc

    def disable_user(
        self,
        username,
        auth_token=None,
    ) -> bool:
        """Disable an existing user"""
        auth_token = auth_token if auth_token else self.default_token
        try:
            for user in self.get_users(auth_token=auth_token):
                if str(user["userPrincipalName"]).startswith(username):
                    self.http_patch(
                        f"{self.base_endpoint}/users/{user['id']}",
                        headers={"Authorization": f"Bearer {auth_token}"},
                        json={"accountEnabled": False},
                    )
                    self.debug(f"Disabled user '{user['userPrincipalName']}'")
                    return True
        except DataSafeHavenMicrosoftGraphException as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not disable user {username}: {str(exc)}"
            ) from exc

    def get_domains(
        self,
        auth_token=None,
    ):
        """Get all available domains"""
        auth_token = auth_token if auth_token else self.default_token
        try:
            endpoint = f"{self.base_endpoint}/domains"
            json_response = self.http_get(
                endpoint,
                headers={"Authorization": f"Bearer {auth_token}"},
            ).json()
        except DataSafeHavenMicrosoftGraphException as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not load list of domains: {str(exc)}"
            ) from exc

        return json_response["value"]

    def get_groups(
        self,
        attributes=None,
        auth_token=None,
    ):
        """Ensure that a group exists"""
        # attributes = attributes if attributes else ["displayName", "id"]
        auth_token = auth_token if auth_token else self.default_token
        try:
            endpoint = f"{self.base_endpoint}/groups"
            if attributes:
                endpoint += f"?$select={','.join(attributes)}"
            json_response = self.http_get(
                endpoint,
                headers={"Authorization": f"Bearer {auth_token}"},
            ).json()
        except DataSafeHavenMicrosoftGraphException as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not load list of groups: {str(exc)}"
            ) from exc

        return json_response["value"]

    def get_id_from_groupname(self, group_name, auth_token=None):
        auth_token = auth_token if auth_token else self.default_token
        try:
            return [
                group
                for group in self.get_groups(auth_token=auth_token)
                if group["displayName"] == group_name
            ][0]["id"]
        except (DataSafeHavenMicrosoftGraphException, IndexError):
            return None

    def get_id_from_username(self, username, auth_token=None):
        auth_token = auth_token if auth_token else self.default_token
        try:
            return [
                user
                for user in self.get_users(auth_token=auth_token)
                if user["mailNickname"] == username
            ][0]["id"]
        except (DataSafeHavenMicrosoftGraphException, IndexError):
            return None

    def get_users(self, attributes=None, auth_token=None):
        """Get users from AzureAD"""
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
                self.linux_schema,
            ]
        )
        auth_token = auth_token if auth_token else self.default_token
        try:
            endpoint = f"{self.base_endpoint}/users"
            if attributes:
                endpoint += f"?$select={','.join(attributes)}"
            json_response = self.http_get(
                endpoint,
                headers={"Authorization": f"Bearer {auth_token}"},
            ).json()
            users = json_response["value"]
        except DataSafeHavenMicrosoftGraphException as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not load list of users: {str(exc)}"
            ) from exc
        try:
            endpoint = f"{self.base_endpoint}/directoryRoles/roleTemplateId={self.role_template_ids['Global Administrator']}/members"
            json_response = self.http_get(
                endpoint,
                headers={"Authorization": f"Bearer {auth_token}"},
            ).json()
            administrators = json_response["value"]
        except DataSafeHavenMicrosoftGraphException as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not load list of administrators: {str(exc)}"
            ) from exc
        for user in users:
            user["isGlobalAdmin"] = any(
                [user["id"] == admin["id"] for admin in administrators]
            )
            for key, value in user.get(self.linux_schema, {}).items():
                user[key] = value
            user[self.linux_schema] = {}
        return users

    def http_delete(self, url, **kwargs):
        try:
            response = requests.delete(url, **kwargs)
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                "Could not execute DELETE request:", str(exc)
            )
        if not response.ok:
            raise DataSafeHavenMicrosoftGraphException(
                "Could not execute DELETE request:", response.content
            )
        return response

    def http_get(self, url, **kwargs):
        try:
            response = requests.get(url, **kwargs)
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                "Could not execute GET request:", str(exc)
            )
        if not response.ok:
            raise DataSafeHavenMicrosoftGraphException(
                "Could not execute GET request:", response.content
            )
        return response

    def http_patch(self, url, **kwargs):
        try:
            response = requests.patch(url, **kwargs)
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                "Could not execute PATCH request:", str(exc)
            )
        if not response.ok:
            raise DataSafeHavenMicrosoftGraphException(
                "Could not execute PATCH request:", response.content
            )
        return response

    def http_post(self, url, **kwargs):
        try:
            response = requests.post(url, **kwargs)
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                "Could not execute POST request:", str(exc)
            )
        if not response.ok:
            raise DataSafeHavenMicrosoftGraphException(
                "Could not execute POST request:", response.content
            )
        time.sleep(30)  # wait for operation to complete
        return response

    def remove_user_from_group(
        self,
        username,
        group_name,
        auth_token=None,
    ):
        """Create a user if it does not already exist"""
        auth_token = auth_token if auth_token else self.default_token
        try:
            user_id = self.get_id_from_username(username, auth_token)
            group_id = self.get_id_from_groupname(group_name, auth_token)
            # Attempt to remove user from group
            response = self.http_delete(
                f"{self.base_endpoint}/groups/{group_id}/members/{user_id}/$ref",
                headers={"Authorization": f"Bearer {auth_token}"},
            )
            if response.ok:
                return True
            return False
        except (DataSafeHavenMicrosoftGraphException, IndexError) as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not create application: {str(exc)}"
            ) from exc

    def list_applications(self, auth_token=None):
        """Get list of application names"""
        auth_token = auth_token if auth_token else self.default_token
        try:
            json_response = self.http_get(
                f"{self.base_endpoint}/applications",
                headers={"Authorization": f"Bearer {auth_token}"},
            ).json()
        except DataSafeHavenMicrosoftGraphException as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not load list of applications: {str(exc)}"
            ) from exc
        return json_response["value"]
