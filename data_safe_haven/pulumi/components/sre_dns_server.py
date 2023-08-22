"""Pulumi component for SRE DNS server"""
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, network, resources

from data_safe_haven.pulumi.common import (
    NetworkingPriorities,
    SREDnsIpRanges,
    SREIpRanges,
    get_ip_address_from_container_group,
)


class SREDnsServerProps:
    """Properties for SREDnsServerComponent"""

    def __init__(
        self,
        location: Input[str],
        sre_index: Input[int],
    ) -> None:
        self.location = location
        subnet_ranges = Output.from_input(sre_index).apply(lambda idx: SREIpRanges(idx))
        self.sre_vnet_prefix = subnet_ranges.apply(lambda r: str(r.vnet))
        self.ip_range_prefix = str(SREDnsIpRanges().vnet)


class SREDnsServerComponent(ComponentResource):
    """Deploy DNS server with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREDnsServerProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:DnsServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-dns",
            opts=child_opts,
        )

        # Define network security group
        nsg = network.NetworkSecurityGroup(
            f"{self._name}_nsg_dns",
            network_security_group_name=f"{stack_name}-nsg-dns",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from attached.",
                    destination_address_prefix=props.ip_range_prefix,
                    destination_port_ranges=["53", "80"],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowSREInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_ANY,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=props.sre_vnet_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny all other inbound traffic.",
                    destination_address_prefix="*",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="DenyAllOtherInbound",
                    priority=NetworkingPriorities.ALL_OTHER,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
                    source_port_range="*",
                ),
                # Outbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound DNS and rules list traffic over the internet.",
                    destination_address_prefix="Internet",
                    destination_port_ranges=["53", "80", "443"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDnsInternetOutbound",
                    priority=NetworkingPriorities.EXTERNAL_INTERNET,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=props.ip_range_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny all other outbound traffic.",
                    destination_address_prefix="*",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAllOtherOutbound",
                    priority=NetworkingPriorities.ALL_OTHER,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
                    source_port_range="*",
                ),
            ],
            opts=child_opts,
        )

        # Deploy dedicated virtual network
        subnet_name = "DnsSubnet"
        virtual_network = network.VirtualNetwork(
            f"{self._name}_virtual_network",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[props.ip_range_prefix],
            ),
            resource_group_name=resource_group.name,
            subnets=[  # Note that we define subnets inline to avoid creation order issues
                # DNS subnet
                network.SubnetArgs(
                    address_prefix=props.ip_range_prefix,
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name=subnet_name,
                    network_security_group=network.NetworkSecurityGroupArgs(id=nsg.id),
                    route_table=None,
                ),
            ],
            virtual_network_name=f"{stack_name}-vnet-dns",
            virtual_network_peerings=[],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=["virtual_network_peerings"]
                ),  # allow peering to SRE virtual network
            ),
        )

        subnet_dns = network.get_subnet_output(
            subnet_name=subnet_name,
            resource_group_name=resource_group.name,
            virtual_network_name=virtual_network.name,
        )

        # Define a network profile
        container_network_profile = network.NetworkProfile(
            f"{self._name}_container_network_profile",
            container_network_interface_configurations=[
                network.ContainerNetworkInterfaceConfigurationArgs(
                    ip_configurations=[
                        network.IPConfigurationProfileArgs(
                            name="ipconfigdns",
                            subnet=network.SubnetArgs(id=subnet_dns.id),
                        )
                    ],
                    name="networkinterfaceconfigdns",
                )
            ],
            network_profile_name=f"{stack_name}-np-dns",
            resource_group_name=resource_group.name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    depends_on=[virtual_network],
                    ignore_changes=[
                        "container_network_interface_configurations"
                    ],  # allow container groups to be registered to this interface
                ),
            ),
        )

        # Define the DNS container group with AdGuard
        allowed_fqdns = [
            "*-jobruntimedata-prod-su1.azure-automation.net",
            "*.clamav.net",
            "database.clamav.net.cdn.cloudflare.net",
            "keyserver.ubuntu.com",
            "time.google.com",
        ]
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-group-dns",
            containers=[
                containerinstance.ContainerArgs(
                    image="ghcr.io/alan-turing-institute/adguard-manager:main",
                    name="adguard",
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="ADMIN_PASSWORD", value="test"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="SPACE_SEPARATED_FILTER_ALLOW",
                            value=" ".join(allowed_fqdns),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="SPACE_SEPARATED_FILTER_DENY", value="*.*"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="UPSTREAM_DNS", value="168.63.129.16"
                        ),
                    ],
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=53,
                            protocol=containerinstance.ContainerGroupNetworkProtocol.UDP,
                        ),
                        containerinstance.ContainerPortArgs(
                            port=80,
                            protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                        ),
                    ],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=1,
                            memory_in_gb=1,
                        ),
                    ),
                    volume_mounts=[],
                ),
            ],
            ip_address=containerinstance.IpAddressArgs(
                ports=[
                    containerinstance.PortArgs(
                        port=80,
                        protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                    )
                ],
                type=containerinstance.ContainerGroupIpAddressType.PRIVATE,
            ),
            network_profile=containerinstance.ContainerGroupNetworkProfileArgs(
                id=container_network_profile.id,
            ),
            os_type=containerinstance.OperatingSystemTypes.LINUX,
            resource_group_name=resource_group.name,
            restart_policy=containerinstance.ContainerGroupRestartPolicy.ALWAYS,
            sku=containerinstance.ContainerGroupSku.STANDARD,
            volumes=[],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    delete_before_replace=True,
                    replace_on_changes=["containers"],
                ),
            ),
        )

        # Register outputs
        self.ip_address = get_ip_address_from_container_group(container_group)
        self.resource_group = resource_group
        self.virtual_network = virtual_network
