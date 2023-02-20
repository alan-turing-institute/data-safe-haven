"""Pulumi dynamic component for AzureAD applications."""
# Standard library imports
from contextlib import suppress
from typing import Any, Dict, Optional

# Third party imports
from pulumi import Input, Output, ResourceOptions
from pulumi.dynamic import CreateResult, DiffResult, Resource, UpdateResult

# Local imports
from data_safe_haven.exceptions import DataSafeHavenMicrosoftGraphException
from data_safe_haven.external.api import GraphApi
from .dsh_resource_provider import DshResourceProvider


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


class AzureADApplicationProvider(DshResourceProvider):
    @staticmethod
    def refresh(props: Dict[str, Any]) -> Dict[str, Any]:
        outs = dict(**props)
        with suppress(Exception):
            graph_api = GraphApi(auth_token=outs["auth_token"])
            if json_response := graph_api.get_application_by_name(
                outs["application_name"]
            ):
                outs["object_id"] = json_response["id"]
                outs["application_id"] = json_response["appId"]
        return outs

    def create(self, props: Dict[str, Any]) -> CreateResult:
        """Create new AzureAD application."""
        outs = dict(**props)
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
            outs["object_id"] = json_response["id"]
            outs["application_id"] = json_response["appId"]
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Failed to create application <fg=green>{props['application_name']}</> in AzureAD.\n{str(exc)}"
            ) from exc
        return CreateResult(
            f"AzureADApplication-{props['application_name']}",
            outs=outs,
        )

    def delete(self, id_: str, props: Dict[str, Any]) -> None:
        """Delete an AzureAD application."""
        try:
            graph_api = GraphApi(
                auth_token=props["auth_token"],
            )
            graph_api.delete_application(props["application_name"])
        except Exception as exc:
            raise DataSafeHavenMicrosoftGraphException(
                f"Failed to delete application <fg=green>{props['application_name']}</> from AzureAD.\n{str(exc)}"
            ) from exc

    def diff(
        self,
        id_: str,
        old_props: Dict[str, Any],
        new_props: Dict[str, Any],
    ) -> DiffResult:
        """Calculate diff between old and new state"""
        # Exclude "auth_token" which should not trigger a diff
        return self.partial_diff(old_props, new_props, ["auth_token"])

    def update(
        self,
        id_: str,
        old_props: Dict[str, Any],
        new_props: Dict[str, Any],
    ) -> UpdateResult:
        """Updating is deleting followed by creating."""
        # Note that we need to use the auth token from new_props
        props = {**old_props}
        props["auth_token"] = new_props["auth_token"]
        self.delete(id_, props)
        updated = self.create(new_props)
        return UpdateResult(outs=updated.outs)


class AzureADApplication(Resource):
    application_id: Output[str]
    object_id: Output[str]
    _resource_type_name = "dsh:AzureADApplication"  # set resource type

    def __init__(
        self,
        name: str,
        props: AzureADApplicationProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__(
            AzureADApplicationProvider(),
            name,
            {"application_id": None, "object_id": None, **vars(props)},
            opts,
        )
