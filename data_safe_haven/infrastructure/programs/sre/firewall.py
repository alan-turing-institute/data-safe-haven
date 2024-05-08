"""Pulumi component for SRE traffic routing"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network

from data_safe_haven.infrastructure.common import get_id_from_subnet


class SREFirewallProps:
    """Properties for SREFirewallComponent"""

    def __init__(
        self,
        location: Input[str],
        resource_group_name: Input[str],
        route_table_name: Input[str],
        subnet_firewall: Input[network.GetSubnetResult],
        subnet_firewall_management: Input[network.GetSubnetResult],
    ) -> None:
        self.location = location
        self.resource_group_name = resource_group_name
        self.route_table_name = route_table_name
        self.subnet_firewall_id = Output.from_input(subnet_firewall).apply(
            get_id_from_subnet
        )
        self.subnet_firewall_management_id = Output.from_input(
            subnet_firewall_management
        ).apply(get_id_from_subnet)


class SREFirewallComponent(ComponentResource):
    """Deploy an SRE firewall with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREFirewallProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:FirewallComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Deploy IP address
        public_ip = network.PublicIPAddress(
            f"{self._name}_pip_firewall",
            public_ip_address_name=f"{stack_name}-pip-firewall",
            public_ip_allocation_method=network.IPAllocationMethod.STATIC,
            resource_group_name=props.resource_group_name,
            sku=network.PublicIPAddressSkuArgs(
                name=network.PublicIPAddressSkuName.STANDARD
            ),
            opts=child_opts,
            tags=child_tags,
        )

        public_ip_management = network.PublicIPAddress(
            f"{self._name}_pip_firewall_management",
            public_ip_address_name=f"{stack_name}-pip-firewall-management",
            public_ip_allocation_method=network.IPAllocationMethod.STATIC,
            resource_group_name=props.resource_group_name,
            sku=network.PublicIPAddressSkuArgs(
                name=network.PublicIPAddressSkuName.STANDARD
            ),
            opts=child_opts,
            tags=child_tags,
        )

        # Deploy firewall
        # Note that a Basic SKU firewall needs a separate management subnet to handle
        # traffic for communicating updates and health metrics to and from Microsoft.
        firewall = network.AzureFirewall(
            f"{self._name}_firewall",
            azure_firewall_name=f"{stack_name}-firewall",
            ip_configurations=[
                network.AzureFirewallIPConfigurationArgs(
                    name="FirewallIpConfiguration",
                    public_ip_address=network.SubResourceArgs(id=public_ip.id),
                    subnet=network.SubResourceArgs(id=props.subnet_firewall_id),
                )
            ],
            location=props.location,
            management_ip_configuration=network.AzureFirewallIPConfigurationArgs(
                name="FirewallManagementIpConfiguration",
                public_ip_address=network.SubResourceArgs(id=public_ip_management.id),
                subnet=network.SubResourceArgs(id=props.subnet_firewall_management_id),
            ),
            resource_group_name=props.resource_group_name,
            sku=network.AzureFirewallSkuArgs(
                name=network.AzureFirewallSkuName.AZF_W_V_NET,
                tier=network.AzureFirewallSkuTier.BASIC,
            ),
            opts=child_opts,
            tags=child_tags,
        )

        # Retrieve the private IP address for the firewall
        private_ip_address = firewall.ip_configurations.apply(
            lambda cfgs: (
                ""
                if not cfgs
                else next(filter(lambda _: _, [cfg.private_ip_address for cfg in cfgs]))
            )
        )

        # Route all connected traffic through the firewall
        network.Route(
            f"{self._name}_route_via_firewall",
            address_prefix="0.0.0.0/0",
            next_hop_ip_address=private_ip_address,
            next_hop_type=network.RouteNextHopType.VIRTUAL_APPLIANCE,
            resource_group_name=props.resource_group_name,
            route_name="ViaFirewall",
            route_table_name=props.route_table_name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=firewall)),
        )
