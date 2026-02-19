"""Wrapper for the Pulumi Log Analytics Workspace component"""

from collections.abc import Mapping

import pulumi
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import operationalinsights


class WrappedLogAnalyticsWorkspaceProps:
    """Properties for the WrappedLogAnalyticsWorkspace"""

    def __init__(
        self,
        location: Input[str],
        resource_group_name: Input[str],
        retention_in_days: Input[int],
        sku: Input[operationalinsights.WorkspaceSkuArgs],
        workspace_name: pulumi.Input[str],
    ) -> None:
        self.location = location
        self.resource_group_name = resource_group_name
        self.retention_in_days = retention_in_days
        self.sku = sku
        self.workspace_name = workspace_name


class WrappedLogAnalyticsWorkspace(ComponentResource):
    def __init__(
        self,
        name: str,
        props: WrappedLogAnalyticsWorkspaceProps,
        opts: pulumi.ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:

        super().__init__("dsh:common:WrappedLogAnalyticsWorkspace", name, {}, opts)

        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        self.workspace = operationalinsights.Workspace(
            resource_name=name,
            location=props.location,
            resource_group_name=props.resource_group_name,
            retention_in_days=props.retention_in_days,
            sku=props.sku,
            workspace_name=props.workspace_name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    parent=self,
                ),
            ),
            tags=child_tags,
        )

        self.resource_group_name: Output[str] = Output.from_input(
            props.resource_group_name
        )
        self.workspace_id: Output[str] = self.workspace.customer_id

        workspace_keys: Output[operationalinsights.GetSharedKeysResult] = Output.all(
            resource_group_name=self.resource_group_name,
            workspace_name=self.workspace.name,
        ).apply(lambda kwargs: operationalinsights.get_shared_keys_output(**kwargs))

        self.workspace_key: Output[str] = Output.secret(
            workspace_keys.apply(
                lambda keys: (
                    keys.primary_shared_key if keys.primary_shared_key else "UNKNOWN"
                )
            )
        )
        self.id = self.workspace.id
        self.name = self.workspace.name

        self.register_outputs(
            {
                "id": self.id,
                "name": self.name,
                "resource_group_name": self.resource_group_name,
                "workspace_id": self.workspace_id,
                "workspace_key": self.workspace_key,
            }
        )
