"""Pulumi component for an Entra Application resource"""

from collections.abc import Mapping
from typing import Any

import pulumi_azuread as entra
from pulumi import ComponentResource, Input, Output, ResourceOptions

from data_safe_haven.functions import replace_separators


class EntraApplicationProps:
    """Properties for EntraApplicationComponent"""

    def __init__(
        self,
        application_name: Input[str],
        application_permissions: list[tuple[str, str]],
        msgraph_service_principal: Input[entra.ServicePrincipal],
        application_kwargs: Mapping[str, Any],
    ) -> None:
        self.application_name = application_name
        self.application_permissions = application_permissions
        self.msgraph_client_id = msgraph_service_principal.client_id
        self.msgraph_object_id = msgraph_service_principal.object_id
        self.application_kwargs = application_kwargs

        # Construct a mapping of all the available application permissions
        self.msgraph_permissions: Output[dict[str, Mapping[str, str]]] = Output.all(
            application=msgraph_service_principal.app_role_ids,
            delegated=msgraph_service_principal.oauth2_permission_scope_ids,
        ).apply(
            lambda kwargs: {
                # 'Role' permissions belong to the application
                "Role": kwargs["application"],
                # 'Scope' permissions are delegated to users
                "Scope": kwargs["delegated"],
            }
        )


class EntraDesktopApplicationProps(EntraApplicationProps):
    """
    Properties for a desktop EntraApplicationComponent.
    See https://learn.microsoft.com/en-us/entra/identity-platform/msal-client-applications)
    """

    def __init__(
        self,
        application_name: Input[str],
        application_permissions: list[tuple[str, str]],
        msgraph_service_principal: Input[entra.ServicePrincipal],
    ):
        super().__init__(
            application_name=application_name,
            application_kwargs={
                "public_client": entra.ApplicationPublicClientArgs(
                    redirect_uris=["urn:ietf:wg:oauth:2.0:oob"]
                )
            },
            application_permissions=application_permissions,
            msgraph_service_principal=msgraph_service_principal,
        )


class EntraWebApplicationProps(EntraApplicationProps):
    """
    Properties for a web EntraApplicationComponent.
    See https://learn.microsoft.com/en-us/entra/identity-platform/msal-client-applications)
    """

    def __init__(
        self,
        application_name: Input[str],
        application_permissions: list[tuple[str, str]],
        msgraph_service_principal: Input[entra.ServicePrincipal],
        redirect_url: Input[str],
    ):
        super().__init__(
            application_name=application_name,
            application_kwargs={
                "web": entra.ApplicationWebArgs(
                    redirect_uris=[redirect_url],
                    implicit_grant=entra.ApplicationWebImplicitGrantArgs(
                        id_token_issuance_enabled=True,
                    ),
                )
            },
            application_permissions=application_permissions,
            msgraph_service_principal=msgraph_service_principal,
        )


class EntraApplicationComponent(ComponentResource):
    """Deploy an Entra application with Pulumi"""

    def __init__(
        self,
        name: str,
        props: EntraApplicationProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:common:EntraApplicationComponent", name, {}, opts)

        # Create the application
        self.application = entra.Application(
            f"{self._name}_application",
            display_name=props.application_name,
            prevent_duplicate_names=True,
            required_resource_accesses=(
                [
                    entra.ApplicationRequiredResourceAccessArgs(
                        resource_accesses=[
                            entra.ApplicationRequiredResourceAccessResourceAccessArgs(
                                id=props.msgraph_permissions[scope][permission],
                                type=scope,
                            )
                            for scope, permission in props.application_permissions
                        ],
                        resource_app_id=props.msgraph_client_id,
                    )
                ]
                if props.application_permissions
                else []
            ),
            sign_in_audience="AzureADMyOrg",
            **props.application_kwargs,
        )

        # Get the service principal for this application
        self.application_service_principal = entra.ServicePrincipal(
            f"{self._name}_application_service_principal",
            client_id=self.application.client_id,
        )

        # Grant admin approval for requested application permissions
        for scope, permission in props.application_permissions:
            if scope == "application":
                entra.AppRoleAssignment(
                    replace_separators(
                        f"{self._name}_application_grant_{scope}_{permission}".lower(),
                        "_",
                    ),
                    app_role_id=props.msgraph_permissions[scope][permission],
                    principal_object_id=self.application_service_principal.object_id,
                    resource_object_id=props.msgraph_object_id,
                )
            if scope == "delegated":
                entra.ServicePrincipalDelegatedPermissionGrant(
                    replace_separators(
                        f"{self._name}_application_delegated_grant_{scope}_{permission}".lower(),
                        "_",
                    ),
                    claim_values=[permission],
                    resource_service_principal_object_id=props.msgraph_object_id,
                    service_principal_object_id=self.application_service_principal.object_id,
                )
