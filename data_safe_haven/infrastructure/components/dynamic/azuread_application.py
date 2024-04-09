"""Pulumi dynamic component for AzureAD applications."""

from contextlib import suppress
from typing import Any

from pulumi import Input, Output, ResourceOptions
from pulumi.dynamic import CreateResult, DiffResult, Resource, UpdateResult

from data_safe_haven.exceptions import DataSafeHavenMicrosoftGraphError
from data_safe_haven.external import GraphApi

from .dsh_resource_provider import DshResourceProvider


class AzureADApplicationProps:
    """Props for the AzureADApplication class"""

    def __init__(
        self,
        application_name: Input[str],
        auth_token: Input[str],
        application_role_assignments: Input[list[str]] | None = None,
        application_secret_name: Input[str] | None = None,
        delegated_role_assignments: Input[list[str]] | None = None,
        public_client_redirect_uri: Input[str] | None = None,
        web_redirect_url: Input[str] | None = None,
    ) -> None:
        self.application_name = application_name
        self.application_role_assignments = application_role_assignments
        self.application_secret_name = application_secret_name
        self.auth_token = Output.secret(auth_token)
        self.delegated_role_assignments = delegated_role_assignments
        self.public_client_redirect_uri = public_client_redirect_uri
        self.web_redirect_url = web_redirect_url


class AzureADApplicationProvider(DshResourceProvider):
    @staticmethod
    def refresh(props: dict[str, Any]) -> dict[str, Any]:
        try:
            outs = dict(**props)
            with suppress(DataSafeHavenMicrosoftGraphError):
                graph_api = GraphApi(
                    auth_token=outs["auth_token"], disable_logging=True
                )
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
            msg = f"Failed to refresh application [green]{props['application_name']}[/] in AzureAD.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc

    def create(self, props: dict[str, Any]) -> CreateResult:
        """Create new AzureAD application."""
        outs = dict(**props)
        try:
            graph_api = GraphApi(auth_token=props["auth_token"], disable_logging=True)
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
            msg = f"Failed to create application [green]{props['application_name']}[/] in AzureAD.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc
        return CreateResult(
            f"AzureADApplication-{props['application_name']}",
            outs=outs,
        )

    def delete(self, id_: str, props: dict[str, Any]) -> None:
        """Delete an AzureAD application."""
        # Use `id` as a no-op to avoid ARG002 while maintaining function signature
        id(id_)
        try:
            graph_api = GraphApi(auth_token=props["auth_token"], disable_logging=True)
            graph_api.delete_application(props["application_name"])
        except Exception as exc:
            msg = f"Failed to delete application [green]{props['application_name']}[/] from AzureAD.\n{exc}"
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
        # Exclude "auth_token" which should not trigger a diff
        return self.partial_diff(old_props, new_props, ["auth_token"])

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
            old_props_["auth_token"] = new_props["auth_token"]
            self.delete(id_, old_props_)
            # Create a new application
            updated = self.create(new_props)
            return UpdateResult(outs=updated.outs)
        except Exception as exc:
            msg = f"Failed to update application [green]{new_props['application_name']}[/] in AzureAD.\n{exc}"
            raise DataSafeHavenMicrosoftGraphError(msg) from exc


class AzureADApplication(Resource):
    application_id: Output[str]
    application_secret: Output[str]
    object_id: Output[str]
    _resource_type_name = "dsh:common:AzureADApplication"  # set resource type

    def __init__(
        self,
        name: str,
        props: AzureADApplicationProps,
        opts: ResourceOptions | None = None,
    ):
        super().__init__(
            AzureADApplicationProvider(),
            name,
            {
                "application_id": None,
                "application_secret": None,
                "object_id": None,
                **vars(props),
            },
            opts,
        )
