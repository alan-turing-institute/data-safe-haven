"""Wrapper for the Pulumi AutomationAccount component"""
from collections.abc import Mapping, Sequence

import pulumi
from pulumi_azure_native import automation


class WrappedAutomationAccount(automation.AutomationAccount):
    def __init__(
        self,
        resource_name: str,
        *,
        automation_account_name: pulumi.Input[str],
        location: pulumi.Input[str],
        name: pulumi.Input[str],
        resource_group_name: pulumi.Input[str],
        sku: pulumi.Input[automation.SkuArgs],
        opts: pulumi.ResourceOptions,
        tags: pulumi.Input[Mapping[str, pulumi.Input[str]]],
    ):
        self.resource_group_name_ = pulumi.Output.from_input(resource_group_name)
        super().__init__(
            resource_name=resource_name,
            automation_account_name=automation_account_name,
            location=location,
            name=name,
            resource_group_name=resource_group_name,
            sku=sku,
            opts=opts,
            tags=tags,
        )

    @property
    def agentsvc_url(self) -> pulumi.Output[str]:
        """
        Gets the URL of the agentsvc.
        """
        return self.automation_hybrid_service_url.apply(
            lambda url: url.replace("jrds", "agentsvc").replace(
                "/automationAccounts/", "/accounts/"
            )
            if url
            else "UNKNOWN"
        )

    @property
    def jrds_url(self) -> pulumi.Output[str]:
        """
        Gets the URL of the jrds.
        """
        return self.automation_hybrid_service_url.apply(
            lambda url: url if url else "UNKNOWN"
        )

    @property
    def primary_key(self) -> pulumi.Output[str]:
        """
        Gets the primary key.
        """
        automation_keys: pulumi.Output[
            Sequence[automation.outputs.KeyResponse] | None
        ] = pulumi.Output.all(
            automation_account_name=self.name,
            resource_group_name=self.resource_group_name,
        ).apply(
            lambda kwargs: automation.list_key_by_automation_account(**kwargs).keys
        )
        return pulumi.Output.secret(
            automation_keys.apply(lambda keys: keys[0].value if keys else "UNKNOWN")
        )

    @property
    def resource_group_name(self) -> pulumi.Output[str]:
        """
        Gets the name of the resource group where this automation account is deployed.
        """
        return self.resource_group_name_
