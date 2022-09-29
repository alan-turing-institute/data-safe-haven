# Standard library imports
import binascii
import os
from typing import Optional

# Third party imports
from pulumi import Input, Output, ResourceOptions
from pulumi.dynamic import (
    Resource,
    ResourceProvider,
    CreateResult,
    DiffResult,
    UpdateResult,
)

# Local imports
from data_safe_haven.exceptions import DataSafeHavenMicrosoftGraphException
from data_safe_haven.external import GraphApi


class AzureADApplicationProps:
    """Props for the AzureADApplication class"""

    def __init__(
        self,
        application_name: Input[str],
        application_url: Input[str],
        auth_token: Input[str],
    ):
        self.application_name = application_name
        self.application_url = application_url
        self.auth_token = auth_token


class _AzureADApplicationProps:
    """Unwrapped version of AzureADApplicationProps"""

    def __init__(
        self,
        application_name: str,
        application_url: str,
        auth_token: str,
    ):
        self.application_name = application_name
        self.application_url = application_url
        self.auth_token = auth_token


class AzureADApplicationProvider(ResourceProvider):
    def create(self, props: _AzureADApplicationProps) -> CreateResult:
        """Create new AzureAD application."""
        try:
            graph_api = GraphApi(
                auth_token=props["auth_token"],
            )
            json_response = graph_api.create_application(
                props["application_name"],
                request_json={
                    "displayName": props["application_name"],
                    "web": {
                        "redirectUris": [props["application_url"]],
                        "implicitGrantSettings": {"enableIdTokenIssuance": True},
                    },
                    "signInAudience": "AzureADMyOrg",
                },
            )
            outputs = {
                "object_id": json_response["id"],
                "application_id": json_response["appId"],
            }
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Failed to create application <fg=green>{props['application_name']}</> in AzureAD."
            ) from exc
        return CreateResult(
            f"AzureADApplication-{binascii.b2a_hex(os.urandom(16)).decode('utf-8')}",
            outs=dict(**outputs, **props),
        )

    def delete(self, id: str, props: _AzureADApplicationProps):
        """Delete an AzureAD application."""
        try:
            graph_api = GraphApi(
                auth_token=props["auth_token"],
            )
            graph_api.delete_application(props["application_name"])
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Failed to delete application <fg=green>{props['application_name']}</> from AzureAD."
            ) from exc

    def diff(
        self,
        id: str,
        oldProps: _AzureADApplicationProps,
        newProps: _AzureADApplicationProps,
    ) -> DiffResult:
        """Calculate diff between old and new state"""
        replaces = []
        # If any of the following are changed then the resource must be replaced
        for property in ("application_name", "application_url"):
            if (property not in oldProps) or (oldProps[property] != newProps[property]):
                replaces.append(property)
        return DiffResult(
            changes=(replaces != []),  # changes are needed
            replaces=replaces,  # replacement is needed
            stables=None,  # list of inputs that are constant
            delete_before_replace=True,  # delete the existing resource before replacing
        )

    def update(
        self,
        id: str,
        oldProps: _AzureADApplicationProps,
        newProps: _AzureADApplicationProps,
    ) -> DiffResult:
        """Updating is deleting followed by creating."""
        # Note that we need to use the auth token from newProps
        props = {**oldProps}
        props["auth_token"] = newProps["auth_token"]
        self.delete(id, props)
        updated = self.create(newProps)
        return UpdateResult(outs={**updated.outs})


class AzureADApplication(Resource):
    application_id: Output[str]
    object_id: Output[str]

    def __init__(
        self,
        name: str,
        props: AzureADApplicationProps,
        opts: Optional[ResourceOptions] = None,
    ):
        self._resource_type_name = "dsh:AzureADApplication"  # set resource type
        super().__init__(
            AzureADApplicationProvider(),
            name,
            {"application_id": None, "object_id": None, **vars(props)},
            opts,
        )
