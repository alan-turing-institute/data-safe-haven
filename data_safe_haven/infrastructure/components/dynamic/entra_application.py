"""Pulumi dynamic component for Entra applications."""

from contextlib import suppress
from typing import Any

from pulumi import Input, Output, ResourceOptions
from pulumi.dynamic import CreateResult, DiffResult, Resource, UpdateResult

from data_safe_haven.exceptions import DataSafeHavenMicrosoftGraphError
from data_safe_haven.external import GraphApi

from .dsh_resource_provider import DshResourceProvider


class EntraApplicationProps:
    """Props for the EntraApplication class"""

    def __init__(
        self,
        application_name: Input[str],
        application_role_assignments: Input[list[str]] | None = None,
        application_secret_name: Input[str] | None = None,
        delegated_role_assignments: Input[list[str]] | None = None,
        public_client_redirect_uri: Input[str] | None = None,
        web_redirect_url: Input[str] | None = None,
    ) -> None:
        self.application_name = application_name
        self.application_role_assignments = application_role_assignments
        self.application_secret_name = application_secret_name
        self.delegated_role_assignments = delegated_role_assignments
        self.public_client_redirect_uri = public_client_redirect_uri
        self.web_redirect_url = web_redirect_url


class EntraApplicationProvider(DshResourceProvider):
    def __init__(self, auth_token: str):
        self.auth_token = auth_token
        super().__init__()

    def create(self, props: dict[str, Any]) -> CreateResult:
        """Create new Entra application."""
        outs = dict(**props)
        try:
            graph_api = GraphApi.from_token(self.auth_token, disable_logging=True)
            request_json = {
                "displayName": props["application_name"],
                "signInAudience": "AzureADMyOrg",
            }
            # Add a web redirection URL if requested
            if props.get("web_redirect_url", None):
                request_json["web"] = {
                    "redirectUris": [props["web_redirect_url"]],
                    "implicitGrantSettings": {"enableIdTokenIssuance": True},
                }
            # Add a public client redirection URL if requested
            if props.get("public_client_redirect_uri", None):
                request_json["publicClient"] = {
                    "redirectUris": [props["public_client_redirect_uri"]],
                }
            json_response = graph_api.create_application(
                props["application_name"],
                application_scopes=props.get("application_role_assignments", []),
                delegated_scopes=props.get("delegated_role_assignments", []),
                request_json=request_json,
            )
            outs["object_id"] = json_response["id"]
            outs["application_id"] = json_response["appId"]

            # Grant requested role permissions
            graph_api.grant_role_permissions(
                outs["application_name"],
                application_role_assignments=props.get(
                    "application_role_assignments", []
                ),
                delegated_role_assignments=props.get("delegated_role_assignments", []),
            )

            # Attach an application secret if requested
            outs["application_secret"] = (
                graph_api.create_application_secret(
                    props["application_name"],
                    props["application_secret_name"],
                )
                if props.get("application_secret_name", None)
                else ""
            )
        except Exception as exc:
            msg = f"Failed to create application '{props['application_name']}' in Entra ID."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc
        return CreateResult(
            f"EntraApplication-{props['application_name']}",
            outs=outs,
        )

    def delete(self, id_: str, props: dict[str, Any]) -> None:
        """Delete an Entra application."""
        # Use `id` as a no-op to avoid ARG002 while maintaining function signature
        id(id_)
        try:
            graph_api = GraphApi.from_token(self.auth_token, disable_logging=True)
            graph_api.delete_application(props["application_name"])
        except Exception as exc:
            msg = f"Failed to delete application '{props['application_name']}' from Entra ID."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def diff(
        self,
        id_: str,
        old_props: dict[str, Any],
        new_props: dict[str, Any],
    ) -> DiffResult:
        """Calculate diff between old and new state"""
        # Use `id` as a no-op to avoid ARG002 while maintaining function signature
        id(id_)
        # We exclude '__provider' from the diff. This is a Base64-encoded pickle of this
        # EntraApplicationProvider instance. This means that it contains self.auth_token
        # and would otherwise trigger a diff each time the auth_token changes. Note that
        # ignoring '__provider' could cause issues if the structure of this class
        # changes in any other way, but this could be fixed by manually deleting the
        # application in the Entra directory.
        return self.partial_diff(old_props, new_props, excluded_props=["__provider"])

    def refresh(self, props: dict[str, Any]) -> dict[str, Any]:
        try:
            outs = dict(**props)
            with suppress(DataSafeHavenMicrosoftGraphError, KeyError):
                graph_api = GraphApi.from_token(self.auth_token, disable_logging=True)
                if json_response := graph_api.get_application_by_name(
                    outs["application_name"]
                ):
                    outs["object_id"] = json_response["id"]
                    outs["application_id"] = json_response["appId"]

                # Ensure that requested role permissions have been granted
                graph_api.grant_role_permissions(
                    outs["application_name"],
                    application_role_assignments=props.get(
                        "application_role_assignments", []
                    ),
                    delegated_role_assignments=props.get(
                        "delegated_role_assignments", []
                    ),
                )
            return outs
        except Exception as exc:
            msg = f"Failed to refresh application '{props['application_name']}' in Entra ID."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def update(
        self,
        id_: str,
        old_props: dict[str, Any],
        new_props: dict[str, Any],
    ) -> UpdateResult:
        """Updating is deleting followed by creating."""
        try:
            # Delete the old application, using the auth token from new_props
            old_props_ = {**old_props}
            self.delete(id_, old_props_)
            # Create a new application
            updated = self.create(new_props)
            return UpdateResult(outs=updated.outs)
        except Exception as exc:
            msg = f"Failed to update application '{new_props['application_name']}' in Entra ID."
            raise DataSafeHavenMicrosoftGraphError(msg) from exc


class EntraApplication(Resource):
    application_id: Output[str]
    application_secret: Output[str]
    object_id: Output[str]
    _resource_type_name = "dsh:common:EntraApplication"  # set resource type

    def __init__(
        self,
        name: str,
        props: EntraApplicationProps,
        auth_token: str,
        opts: ResourceOptions | None = None,
    ):
        super().__init__(
            EntraApplicationProvider(auth_token),
            name,
            {
                "application_id": None,
                "application_secret": None,
                "object_id": None,
                **vars(props),
            },
            opts,
        )
