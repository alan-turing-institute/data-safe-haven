"""Pulumi component for SRE Entra resources"""

from collections.abc import Mapping

from pulumi import ComponentResource, ResourceOptions
from pulumi_azuread import Group

from data_safe_haven.functions import replace_separators


class SREEntraProps:
    """Properties for SREEntraComponent"""

    def __init__(
        self,
        group_names: Mapping[str, str],
    ) -> None:
        self.group_names = group_names


class SREEntraComponent(ComponentResource):
    """Deploy SRE Entra resources with Pulumi"""

    def __init__(
        self,
        name: str,
        props: SREEntraProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:EntraComponent", name, {}, opts)

        for group_id, group_description in props.group_names.items():
            Group(
                replace_separators(f"{self._name}_group_{group_id}", "_"),
                description=group_description,
                display_name=group_description,
                mail_enabled=False,
                prevent_duplicate_names=True,
                security_enabled=True,
            )
