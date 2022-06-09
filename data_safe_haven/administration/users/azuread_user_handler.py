"""Interface to Azure for a Data Safe Haven environment"""
# Local imports
from data_safe_haven.exceptions import DataSafeHavenMicrosoftGraphException
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.helpers.graph_api import GraphApi, AzureADUser


class AzureADUserHandler(LoggingMixin):
    """Interact with an Azure Active Directory"""

    def __init__(self, tenant_id, application_id, application_secret, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # self.schema_id = "extj8xolrvw_linux"  # this is the "Extension with Properties for Linux User and Groups" extension
        self.application_id = application_id
        self.application_secret = application_secret
        self.token_ = None
        self.graph_api = GraphApi(tenant_id=tenant_id)

    @property
    def token(self):
        if not self.token_:
            self.token_ = self.graph_api.access_token(
                self.application_id, self.application_secret
            )
        return self.token_

    def update_users(self):
        """Ensure that all users have Linux attributes"""
        users = self.graph_api.get_users(
            self.token, ["id", "userPrincipalName", "mail", AzureADUser.schema_name]
        )

        next_uid = max([int(u.uid) + 1 if u.uid else 0 for u in users] + [10000])
        for user in users:
            # Get username from userPrincipalName
            username = user.userPrincipalName.split("@")[0]
            if not user.uid:
                # Set UID to the next unused one
                user.uid = next_uid
                next_uid += 1
                self.debug(f"Added uid {user.uid} to user {username}")
            if not user.gidnumber:
                user.gidnumber = "100"
                self.debug(f"Added homedir {user.gidnumber} to user {username}")
            if not user.homedir:
                user.homedir = f"/home/{username}"
                self.debug(f"Added homedir {user.homedir} to user {username}")
            if not user.shell:
                user.shell = "/bin/bash"
                self.debug(f"Added shell {user.shell} to user {username}")
            if not user.user:
                user.user = username
                self.debug(f"Added username {user.user} to user {username}")
            # Ensure that the remote user matches the local model
            patch_json = {
                AzureADUser.schema_name: {
                    "uid": user.uid,
                    "gidnumber": user.gidnumber,
                    "shell": user.shell,
                    "homedir": user.homedir,
                    "user": user.user,
                }
            }
            try:
                self.graph_api.http_patch(
                    f"{self.graph_api.base_endpoint}/users/{user.oid}",
                    headers={"Authorization": f"Bearer {self.token}"},
                    json=patch_json,
                )
                self.info(f"Updated user {user.userPrincipalName}.")
            except DataSafeHavenMicrosoftGraphException as exc:
                self.error(
                    f"Failed to update user {user.userPrincipalName}: {str(exc)}"
                )
