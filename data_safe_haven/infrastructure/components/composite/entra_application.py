"""Pulumi component for an Entra Application resource"""

from collections.abc import Mapping

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
    ) -> None:
        self.application_name = application_name
        self.application_permissions = application_permissions
        self.msgraph_client_id = msgraph_service_principal.client_id
        self.msgraph_object_id = msgraph_service_principal.object_id

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
            sign_in_audience="AzureADMyOrg",
            public_client={"redirectUris": ["urn:ietf:wg:oauth:2.0:oob"]},
            required_resource_accesses=[
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
            ],
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
