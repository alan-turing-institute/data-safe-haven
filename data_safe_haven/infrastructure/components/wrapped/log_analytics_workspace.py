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

        workspace = operationalinsights.Workspace(
            resource_name=name,
            location=props.location,
            resource_group_name=props.resource_group_name,
            retention_in_days=props.retention_in_days,
            sku=props.sku,
            workspace_name=props.workspace_name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=self)),
            tags=child_tags,
        )

        self.resource_group_name: Output[str] = workspace.resource_group_name_
        self.workspace_id: Output[str] = workspace.customer_id
        self.workspace_key: Output[str] = Output.secret(
            operationalinsights.get_shared_keys_output(
                resource_group_name=workspace.resource_group_name,
                workspace_name=workspace.name,
            ).primary_shared_key
        )
        self.id = workspace.id
        self.name = workspace.name

        self.register_outputs(
            {
                "id": self.id,
                "name": self.name,
                "resource_group_name": self.resource_group_name,
                "workspace_id": self.workspace_id,
                "workspace_key": self.workspace_key,
            }
        )
