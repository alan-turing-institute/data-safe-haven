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


class AzureADUser:
    schema_name = "extj8xolrvw_linux"  # this is the "Extension with Properties for Linux User and Groups" extension

    def __init__(self, **kwargs):
        schema_props = kwargs.get(self.schema_name, {})
        self.gecos = kwargs.get("gecos", None)
        self.gid = kwargs.get("gid", None)
        self.gidnumber = schema_props.get("gidnumber", None)
        self.group = schema_props.get("group", None)
        self.homedir = schema_props.get("homedir", None)
        self.mail = kwargs.get("mail", None)
        self.members = schema_props.get("members", None)
        self.oid = kwargs.get("id", None)
        self.passwd = schema_props.get("passwd", None)
        self.shell = schema_props.get("shell", None)
        self.uid = schema_props.get("uid", None)
        self.user = schema_props.get("user", None)
        self.userPrincipalName = kwargs.get("userPrincipalName", None)

    def __str__(self):
        attrs = []
        if self.gecos:
            attrs.append(f"gecos {self.gecos}")
        if self.gid:
            attrs.append(f"gid {self.gid}")
        if self.gidnumber:
            attrs.append(f"gidnumber {self.gidnumber}")
        if self.group:
            attrs.append(f"group {self.group}")
        if self.homedir:
            attrs.append(f"homedir {self.homedir}")
        if self.mail:
            attrs.append(f"mail {self.mail}")
        if self.members:
            attrs.append(f"members {self.members}")
        if self.oid:
            attrs.append(f"oid {self.oid}")
        if self.passwd:
            attrs.append(f"passwd {self.passwd}")
        if self.shell:
            attrs.append(f"shell {self.shell}")
        if self.uid:
            attrs.append(f"uid {self.uid}")
        if self.user:
            attrs.append(f"user {self.user}")
        if self.userPrincipalName:
            attrs.append(f"userPrincipalName {self.userPrincipalName}")
        return "; ".join(attrs)


class GraphApi(LoggingMixin):
    to_uuid = {
        "Group.Read.All": "5b567255-7703-4780-807c-7be8301ae99b",
        "Group.ReadWrite.All": "62a82d76-70ea-41e2-9197-370581804d09",
        "GroupMember.Read.All": "bc024368-1153-4739-b217-4326f2e966d0",
        "User.ReadWrite.All": "741f803b-c850-494e-b5df-cde7c675a1ca",
        "User.Read.All": "df021288-bdef-4463-88db-98f22de89214",
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
                authority=f"https://login.microsoftonline.com/{self.tenant_id}",
            )
            # Initiate device code flow
            flow = app.initiate_device_flow(scopes=self.default_scopes)
            if "user_code" not in flow:
                raise DataSafeHavenMicrosoftGraphException(
                    "Could not initiate device login"
                )
            self.info(
                "Please use credentials for a <fg=green>global administrator</> for the Azure Active Directory where your users are stored."
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

    def application(
        self,
        application_name,
        auth_token=None,
        application_scopes=[],
        delegated_scopes=[],
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
                "id": self.to_uuid[application_scope],
                "type": "Role",
            }
            for application_scope in application_scopes
        ] + [
            {
                "id": self.to_uuid[delegated_scope],
                "type": "Scope",
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
            json_response = self.json_post(
                f"{self.base_endpoint}/applications",
                headers={"Authorization": f"Bearer {auth_token}"},
                json=request_json,
            )
        except DataSafeHavenMicrosoftGraphException as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not create application: {str(exc)}"
            ) from exc
        self.info(
            f"Created new application '<fg=green>{json_response['displayName']}</>'.",
            overwrite=True,
        )

        # Grant admin consent for the requested scopes
        self.info(
            f"Please visit <fg=green>https://login.microsoftonline.com/{self.tenant_id}/adminconsent?client_id={json_response['appId']}&redirect_uri=https://login.microsoftonline.com/common/oauth2/nativeclient</> to provide admin consent for requested permissions."
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
            json_response = self.json_post(
                f"{self.base_endpoint}/applications/{application_json['id']}/addPassword",
                headers={"Authorization": f"Bearer {auth_token}"},
                json=request_json,
            )
        except DataSafeHavenMicrosoftGraphException as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not create application secret: {str(exc)}"
            ) from exc
        return json_response["secretText"]

    def get_users(self, auth_token, attributes):
        try:
            endpoint = f"{self.base_endpoint}/users?$select={','.join(attributes)}"
            json_response = self.json_get(
                endpoint,
                headers={"Authorization": f"Bearer {auth_token}"},
            )
        except DataSafeHavenMicrosoftGraphException as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not load list of users: {str(exc)}"
            ) from exc

        return [AzureADUser(**props) for props in json_response["value"]]

    def json_get(self, url, **kwargs):
        response = requests.get(url, **kwargs)
        if not response.ok:
            raise DataSafeHavenMicrosoftGraphException(response.content)
        return response.json()

    def json_patch(self, url, **kwargs):
        response = requests.patch(url, **kwargs)
        if not response.ok:
            raise DataSafeHavenMicrosoftGraphException(response.content)
        return response.json()

    def json_post(self, url, **kwargs):
        response = requests.post(url, **kwargs)
        if not response.ok:
            raise DataSafeHavenMicrosoftGraphException(response.content)
        time.sleep(30)  # wait for operation to complete
        return response.json()

    def list_applications(self, auth_token=None):
        """Get list of application names"""
        auth_token = auth_token if auth_token else self.default_token
        try:
            json_response = self.json_get(
                f"{self.base_endpoint}/applications",
                headers={"Authorization": f"Bearer {auth_token}"},
            )
        except DataSafeHavenMicrosoftGraphException as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Could not load list of applications: {str(exc)}"
            ) from exc
        return json_response["value"]

    def access_token(self, application_id, application_secret):
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
