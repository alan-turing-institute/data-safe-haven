# Standard library imports
from typing import Optional, Sequence

# Third party imports
from pulumi import ComponentResource, Input, ResourceOptions, Output
from pulumi_azure_native import network
from data_safe_haven.helpers import AzureIPv4Range


class SHMNetworkingProps:
    """Properties for SHMNetworkingComponent"""

    def __init__(
        self,
        fqdn: Input[str],
        resource_group_name: Input[str],
        public_ip_range_admins: Input[Sequence[str]],
        ip_range_vnet: Optional[Input[Sequence[str]]] = [
            "10.0.0.0",
            "10.0.255.255",
        ],
        ip_range_firewall: Optional[
            Input[Sequence[str]]
        ] = [  # must be at least /26 in size
            "10.0.0.0",
            "10.0.0.63",
        ],
        ip_range_vpn_gateway: Optional[Input[Sequence[str]]] = [
            "10.0.0.64",
            "10.0.0.127",
        ],
        ip_range_monitoring: Optional[Input[Sequence[str]]] = [
            "10.0.0.128",
            "10.0.0.159",
        ],
        ip_range_update_servers: Optional[Input[Sequence[str]]] = [
            "10.0.0.160",
            "10.0.0.191",
        ],
        ip_range_users: Optional[Input[Sequence[str]]] = [
            "10.0.0.192",
            "10.0.0.223",
        ],
    ):
        self.ip_range_vnet = ip_range_vnet
        self.ip_range_firewall = ip_range_firewall
        self.ip_range_vpn_gateway = ip_range_vpn_gateway
        self.ip_range_monitoring = ip_range_monitoring
        self.ip_range_update_servers = ip_range_update_servers
        self.ip_range_users = ip_range_users
        self.fqdn = fqdn
        self.public_ip_range_admins = public_ip_range_admins
        self.resource_group_name = resource_group_name


class SHMNetworkingComponent(ComponentResource):
    """Deploy SHM networking with Pulumi"""

    def __init__(
        self, name: str, props: SHMNetworkingProps, opts: ResourceOptions = None
    ):
        super().__init__("dsh:shm_networking:SHMNetworkingComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Set address prefixes from ranges
        virtual_network_iprange = AzureIPv4Range(*props.ip_range_vnet)
        subnet_firewall_iprange = AzureIPv4Range(*props.ip_range_firewall)
        subnet_vpn_gateway_iprange = AzureIPv4Range(*props.ip_range_vpn_gateway)
        subnet_monitoring_iprange = AzureIPv4Range(*props.ip_range_monitoring)
        subnet_update_servers_iprange = AzureIPv4Range(*props.ip_range_update_servers)
        subnet_users_iprange = AzureIPv4Range(*props.ip_range_users)

        # Define NSGs
        nsg_monitoring = network.NetworkSecurityGroup(
            "nsg_monitoring",
            network_security_group_name=f"nsg-{self._name}-monitoring",
            resource_group_name=props.resource_group_name,
            security_rules=[],
            opts=child_opts,
        )
        nsg_update_servers = network.NetworkSecurityGroup(
            "nsg_update_servers",
            network_security_group_name=f"nsg-{self._name}-update-servers",
            resource_group_name=props.resource_group_name,
            security_rules=[],
            opts=child_opts,
        )
        nsg_users = network.NetworkSecurityGroup(
            "nsg_users",
            network_security_group_name=f"nsg-{self._name}-users",
            resource_group_name=props.resource_group_name,
            security_rules=[
                network.SecurityRuleArgs(
                    access="Allow",
                    description="Allow inbound RDS to domain controllers.",
                    destination_address_prefix=str(subnet_users_iprange),
                    destination_port_ranges=["3389"],
                    direction="Inbound",
                    name="AllowRDPInbound",
                    priority=100,
                    protocol="TCP",
                    source_address_prefixes=props.public_ip_range_admins,
                    source_port_range="*",
                ),
            ],
            opts=child_opts,
        )

        # Define the virtual network with inline subnets
        virtual_network = network.VirtualNetwork(
            "virtual_network",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[str(virtual_network_iprange)],
            ),
            resource_group_name=props.resource_group_name,
            subnets=[  # Note that we need to define subnets inline or they will be destroyed/recreated on a new run
                network.SubnetArgs(
                    address_prefix=str(subnet_firewall_iprange),
                    name="AzureFirewallSubnet",  # the firewall subnet MUST be named 'AzureFirewallSubnet'. See https://docs.microsoft.com/en-us/azure/firewall/tutorial-firewall-deploy-portal
                    network_security_group=None,  # the firewall subnet must NOT have an NSG
                ),
                network.SubnetArgs(
                    address_prefix=str(subnet_vpn_gateway_iprange),
                    name="GatewaySubnet",  # the VPN gateway subnet MUST be named 'GatewaySubnet'. See https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-vpn-faq#do-i-need-a-gatewaysubnet
                    network_security_group=None,  # the VPN gateway subnet must NOT have an NSG
                ),
                network.SubnetArgs(
                    address_prefix=str(subnet_monitoring_iprange),
                    name="MonitoringSubnet",
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_monitoring.id
                    ),
                ),
                network.SubnetArgs(
                    address_prefix=str(subnet_update_servers_iprange),
                    name="UpdateServersSubnet",
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_update_servers.id
                    ),
                ),
                network.SubnetArgs(
                    address_prefix=str(subnet_users_iprange),
                    name="UsersSubnet",
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_users.id
                    ),
                ),
            ],
            virtual_network_name=f"vnet-{self._name}",
            opts=child_opts,
        )

        # Define SHM DNS zone
        dns_zone = network.Zone(
            "dns_zone",
            location="Global",
            resource_group_name=props.resource_group_name,
            zone_name=props.fqdn,
            zone_type="Public",
        )

        # Register outputs
        self.subnet_users_iprange = subnet_users_iprange
        self.resource_group_name = Output.from_input(props.resource_group_name)
        self.virtual_network = virtual_network
