"""Pulumi component for SHM networking"""
# Standard library imports
from typing import Optional, Sequence

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

# Local imports
from data_safe_haven.external.interface import AzureIPv4Range


class SHMNetworkingProps:
    """Properties for SHMNetworkingComponent"""

    def __init__(
        self,
        fqdn: Input[str],
        location: Input[str],
        public_ip_range_admins: Input[Sequence[str]],
        record_domain_verification: Input[str],
        ip_range_vnet: Optional[Input[Sequence[str]]],
        ip_range_firewall: Optional[Input[Sequence[str]]],
        ip_range_vpn_gateway: Optional[Input[Sequence[str]]],
        ip_range_monitoring: Optional[Input[Sequence[str]]],
        ip_range_update_servers: Optional[Input[Sequence[str]]],
        ip_range_identity: Optional[Input[Sequence[str]]],
    ):
        self.fqdn = fqdn
        self.ip_range_firewall = (
            ip_range_firewall if ip_range_firewall else ["10.0.0.0", "10.0.0.63"]
        )  # must be at least /26 in size
        self.ip_range_identity = (
            ip_range_identity if ip_range_identity else ["10.0.0.192", "10.0.0.223"]
        )
        self.ip_range_monitoring = (
            ip_range_monitoring if ip_range_monitoring else ["10.0.0.128", "10.0.0.159"]
        )
        self.ip_range_update_servers = (
            ip_range_update_servers
            if ip_range_update_servers
            else ["10.0.0.160", "10.0.0.191"]
        )
        self.ip_range_vnet = (
            ip_range_vnet if ip_range_vnet else ["10.0.0.0", "10.0.255.255"]
        )
        self.ip_range_vpn_gateway = (
            ip_range_vpn_gateway
            if ip_range_vpn_gateway
            else ["10.0.0.64", "10.0.0.127"]
        )
        self.location = location
        self.public_ip_range_admins = public_ip_range_admins
        self.record_domain_verification = record_domain_verification
        self.subnet_firewall_name = "AzureFirewallSubnet"  # This name is forced by https://docs.microsoft.com/en-us/azure/firewall/tutorial-firewall-deploy-portal
        self.subnet_identity_name = "IdentitySubnet"
        self.subnet_monitoring_name = "MonitoringSubnet"
        self.subnet_update_servers_name = "UpdateServersSubnet"
        self.subnet_vpn_gateway_name = "GatewaySubnet"  # This name is forced by https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-vpn-faq#do-i-need-a-gatewaysubnet


class SHMNetworkingComponent(ComponentResource):
    """Deploy SHM networking with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        shm_name: str,
        props: SHMNetworkingProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:shm:SHMNetworkingComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"rg-{stack_name}-networking",
        )

        # Set address prefixes from ranges
        virtual_network_iprange = Output.from_input(props.ip_range_vnet).apply(
            lambda iprange: AzureIPv4Range(*iprange)
        )
        subnet_firewall_iprange = Output.from_input(props.ip_range_firewall).apply(
            lambda iprange: AzureIPv4Range(*iprange)
        )
        subnet_vpn_gateway_iprange = Output.from_input(
            props.ip_range_vpn_gateway
        ).apply(lambda iprange: AzureIPv4Range(*iprange))
        subnet_monitoring_iprange = Output.from_input(props.ip_range_monitoring).apply(
            lambda iprange: AzureIPv4Range(*iprange)
        )
        subnet_update_servers_iprange = Output.from_input(
            props.ip_range_update_servers
        ).apply(lambda iprange: AzureIPv4Range(*iprange))
        subnet_identity_iprange = Output.from_input(props.ip_range_identity).apply(
            lambda iprange: AzureIPv4Range(*iprange)
        )

        # Define NSGs
        nsg_monitoring = network.NetworkSecurityGroup(
            f"{self._name}_nsg_monitoring",
            network_security_group_name=f"nsg-{stack_name}-monitoring",
            resource_group_name=resource_group.name,
            security_rules=[],
            opts=child_opts,
        )
        nsg_update_servers = network.NetworkSecurityGroup(
            f"{self._name}_nsg_update_servers",
            network_security_group_name=f"nsg-{stack_name}-update-servers",
            resource_group_name=resource_group.name,
            security_rules=[],
            opts=child_opts,
        )
        nsg_identity = network.NetworkSecurityGroup(
            f"{self._name}_nsg_identity",
            network_security_group_name=f"nsg-{stack_name}-identity",
            resource_group_name=resource_group.name,
            security_rules=[
                network.SecurityRuleArgs(
                    access="Allow",
                    description="Allow inbound LDAP to domain controllers.",
                    destination_address_prefix=str(subnet_identity_iprange),
                    destination_port_ranges=["389", "636"],
                    direction="Inbound",
                    name="AllowLDAPClientUDPInbound",
                    priority=1000,
                    protocol="UDP",
                    source_address_prefix="*",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access="Allow",
                    description="Allow inbound LDAP to domain controllers.",
                    destination_address_prefix=str(subnet_identity_iprange),
                    destination_port_ranges=["389", "636"],
                    direction="Inbound",
                    name="AllowLDAPClientTCPInbound",
                    priority=1100,
                    protocol="TCP",
                    source_address_prefix="*",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access="Allow",
                    description="Allow inbound RDP connections from admins.",
                    destination_address_prefix=str(subnet_identity_iprange),
                    destination_port_ranges=["3389"],
                    direction="Inbound",
                    name="AllowAdminRDPInbound",
                    priority=2000,
                    protocol="TCP",
                    source_address_prefixes=props.public_ip_range_admins,
                    source_port_range="*",
                ),
            ],
            opts=child_opts,
        )

        # Define route table
        route_table = network.RouteTable(
            f"{self._name}_route_table",
            location=props.location,
            resource_group_name=resource_group.name,
            route_table_name=f"{stack_name}-route",
            routes=[],
            opts=ResourceOptions.merge(
                ResourceOptions(
                    ignore_changes=["routes"]
                ),  # allow routes to be added in other modules
                child_opts,
            ),
        )

        # Define the virtual network with inline subnets
        virtual_network = network.VirtualNetwork(
            f"{self._name}_virtual_network",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[str(virtual_network_iprange)],
            ),
            resource_group_name=resource_group.name,
            subnets=[  # Note that we need to define subnets inline or they will be destroyed/recreated on a new run
                network.SubnetArgs(
                    address_prefix=str(subnet_firewall_iprange),
                    name=props.subnet_firewall_name,
                    network_security_group=None,  # the firewall subnet must NOT have an NSG
                ),
                network.SubnetArgs(
                    address_prefix=str(subnet_vpn_gateway_iprange),
                    name=props.subnet_vpn_gateway_name,
                    network_security_group=None,  # the VPN gateway subnet must NOT have an NSG
                ),
                network.SubnetArgs(
                    address_prefix=str(subnet_monitoring_iprange),
                    name=props.subnet_monitoring_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_monitoring.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                network.SubnetArgs(
                    address_prefix=str(subnet_update_servers_iprange),
                    name=props.subnet_update_servers_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_update_servers.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                network.SubnetArgs(
                    address_prefix=str(subnet_identity_iprange),
                    name=props.subnet_identity_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_identity.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
            ],
            virtual_network_name=f"vnet-{stack_name}",
            opts=child_opts,
        )

        # Define SHM DNS zone
        dns_zone = network.Zone(
            f"{self._name}_dns_zone",
            location="Global",
            resource_group_name=resource_group.name,
            zone_name=props.fqdn,
            zone_type=network.ZoneType.PUBLIC,
        )
        caa_record = network.RecordSet(
            f"{self._name}_caa_record",
            caa_records=[
                network.CaaRecordArgs(
                    flags=0,
                    tag="issue",
                    value="letsencrypt.org",
                )
            ],
            record_type="CAA",
            relative_record_set_name="@",
            resource_group_name=resource_group.name,
            ttl=30,
            zone_name=dns_zone.name,
            opts=child_opts,
        )
        domain_verification_record = network.RecordSet(
            f"{self._name}_domain_verification_record",
            record_type="TXT",
            relative_record_set_name="@",
            resource_group_name=resource_group.name,
            ttl=3600,
            txt_records=[
                network.TxtRecordArgs(
                    value=[props.record_domain_verification],
                )
            ],
            zone_name=dns_zone.name,
            opts=child_opts,
        )

        # Set up private link domains
        for private_link_domain in [
            "agentsvc.azure-automation.net",
            "azure-automation.net",  # note this must come after 'agentsvc.azure-automation.net'
            "blob.core.windows.net",
            "monitor.azure.com",
            "ods.opinsights.azure.com",
            "oms.opinsights.azure.com",
        ]:
            private_zone = network.PrivateZone(
                f"{self._name}_private_zone_{private_link_domain}",
                location="Global",
                private_zone_name=f"privatelink.{private_link_domain}",
                resource_group_name=resource_group.name,
            )
            virtual_network_link = network.VirtualNetworkLink(
                f"{self._name}_private_zone_{private_link_domain}_vnet_link",
                location="Global",
                private_zone_name=private_zone.name,
                registration_enabled=False,
                resource_group_name=resource_group.name,
                virtual_network=network.SubResourceArgs(id=virtual_network.id),
                virtual_network_link_name=f"link-to-vnet-{stack_name}",
            )

        # Extract subnets
        subnet_firewall = network.get_subnet_output(
            subnet_name=props.subnet_firewall_name,
            resource_group_name=resource_group.name,
            virtual_network_name=virtual_network.name,
        )

        # Register outputs
        self.dns_zone_nameservers = dns_zone.name_servers
        self.domain_controller_private_ip = str(subnet_identity_iprange.available()[0])
        self.resource_group_name = Output.from_input(resource_group.name)
        self.route_table = route_table
        self.subnet_firewall = subnet_firewall
        self.subnet_firewall_name = Output.from_input(props.subnet_firewall_name)
        self.subnet_identity_iprange = subnet_identity_iprange
        self.subnet_identity_name = Output.from_input(props.subnet_identity_name)
        self.subnet_monitoring_name = Output.from_input(props.subnet_monitoring_name)
        self.subnet_monitoring = network.get_subnet(
            resource_group_name=resource_group.name,
            subnet_name=props.subnet_monitoring_name,
            virtual_network_name=virtual_network.name,
        )
        self.subnet_update_servers_iprange = subnet_update_servers_iprange
        self.subnet_update_servers_name = Output.from_input(
            props.subnet_update_servers_name
        )
        self.subnet_vpn_gateway_name = Output.from_input(props.subnet_vpn_gateway_name)
        self.virtual_network = virtual_network

        # Register exports
        self.exports = {
            "virtual_network_name": virtual_network.name,
        }
