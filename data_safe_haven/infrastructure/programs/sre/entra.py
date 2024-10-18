"""Pulumi component for SRE Entra resources"""

from collections.abc import Mapping

import pulumi_azuread as entra
from pulumi import ComponentResource, Input, Output, ResourceOptions

from data_safe_haven.functions import replace_separators
from data_safe_haven.infrastructure.components.composite.entra_application import (
    EntraApplicationComponent,
    EntraApplicationProps,
)


class SREEntraProps:
    """Properties for SREEntraComponent"""

    def __init__(
        self,
        group_names: Mapping[str, str],
        shm_name: Input[str],
        sre_name: Input[str],
    ) -> None:
        self.group_names = group_names
        self.shm_name = shm_name
        self.sre_name = sre_name


class SREEntraComponent(ComponentResource):
    """Deploy SRE Entra resources with Pulumi"""

    def __init__(
        self,
        name: str,
        props: SREEntraProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:EntraComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        # Create Entra groups
        for group_name, group_description in props.group_names.items():
            entra.Group(
                replace_separators(f"{self._name}_group_{group_name}", "_"),
                description=group_description,
                display_name=group_description,
                mail_enabled=False,
                prevent_duplicate_names=True,
                security_enabled=True,
            )

        # Get the Microsoft Graph service principal
        well_known = entra.get_application_published_app_ids_output()
        msgraph_service_principal = entra.ServicePrincipal(
            f"{self._name}_microsoft_graph_service_principal",
            client_id=well_known.apply(
                lambda app_ids: app_ids.result["MicrosoftGraph"]
            ),
            use_existing=True,
        )

        # Identity application
        # - needs read-only permissions for users/groups
        # - needs delegated permission to read users (for validating log-in attempts)
        # - needs an application secret for authentication
        self.identity_application = EntraApplicationComponent(
            f"{self._name}_identity",
            EntraApplicationProps(
                application_name=Output.concat(
                    "Data Safe Haven (",
                    props.shm_name,
                    " - ",
                    props.sre_name,
                    ") Identity Service Principal",
                ),
                application_permissions=[
                    ("Role", "User.Read.All"),
                    ("Role", "GroupMember.Read.All"),
                    ("Scope", "User.Read.All"),
                ],
                msgraph_service_principal=msgraph_service_principal,
            ),
            opts=child_opts,
        )

        # Add an application password
        self.identity_application_secret = entra.ApplicationPassword(
            f"{self._name}_identity_application_secret",
            application_id=self.identity_application.application.id,
            display_name="Apricot Authentication Secret",
        )
