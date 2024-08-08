"""Wrapper for the Pulumi Log Analytics Workspace component"""

from collections.abc import Mapping

import pulumi
from pulumi_azure_native import operationalinsights


class WrappedLogAnalyticsWorkspace(operationalinsights.Workspace):
    def __init__(
        self,
        resource_name: str,
        *,
        location: pulumi.Input[str],
        resource_group_name: pulumi.Input[str],
        retention_in_days: pulumi.Input[int],
        sku: pulumi.Input[operationalinsights.WorkspaceSkuArgs],
        workspace_name: pulumi.Input[str],
        opts: pulumi.ResourceOptions,
        tags: pulumi.Input[Mapping[str, pulumi.Input[str]]],
    ):
        self.resource_group_name_ = pulumi.Output.from_input(resource_group_name)
        super().__init__(
            resource_name=resource_name,
            location=location,
            resource_group_name=resource_group_name,
            retention_in_days=retention_in_days,
            sku=sku,
            workspace_name=workspace_name,
            opts=opts,
            tags=tags,
        )

    @property
    def resource_group_name(self) -> pulumi.Output[str]:
        """
        Gets the name of the resource group where this log analytics workspace is deployed.
        """
        return self.resource_group_name_

    @property
    def workspace_id(self) -> pulumi.Output[str]:
        """
        Gets the ID of this workspace.
        """
        return self.customer_id

    @property
    def workspace_key(self) -> pulumi.Output[str]:
        """
        Gets the key for this workspace.
        """
        workspace_keys: pulumi.Output[operationalinsights.GetSharedKeysResult] = (
            pulumi.Output.all(
                resource_group_name=self.resource_group_name,
                workspace_name=self.name,
            ).apply(lambda kwargs: operationalinsights.get_shared_keys_output(**kwargs))
        )
        return pulumi.Output.secret(
            workspace_keys.apply(
                lambda keys: (
                    keys.primary_shared_key if keys.primary_shared_key else "UNKNOWN"
                )
            )
        )
