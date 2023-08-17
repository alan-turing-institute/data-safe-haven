"""Pulumi component for SRE DNS management"""
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

# from data_safe_haven.external import AzureIPv4Range
from data_safe_haven.functions import alphanumeric, ordered_private_dns_zones
from data_safe_haven.pulumi.common import NetworkingPriorities, SRESubnetRanges


class SREDnsServerProps:
    """Properties for SREDnsServerComponent"""

    def __init__(
        self,
        resource_group: Input[resources.ResourceGroup],
    ) -> None:
        self.resource_group = resource_group


class SREDnsServerComponent(ComponentResource):
    """Deploy DNS management with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREDnsServerProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:DnsServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
