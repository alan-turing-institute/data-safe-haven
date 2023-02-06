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
    ):
        self.fqdn = fqdn
        self.location = location
        self.public_ip_range_admins = public_ip_range_admins
        self.record_domain_verification = record_domain_verification


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
        virtual_network_iprange = AzureIPv4Range("10.0.0.0", "10.0.255.255")
        # Firewall subnet must be at least /26 in size
        subnet_firewall_iprange = virtual_network_iprange.next_subnet(64)
        # VPN gateway subnet must be at least /29 in size
        subnet_vpn_gateway_iprange = virtual_network_iprange.next_subnet(64)
        subnet_monitoring_iprange = virtual_network_iprange.next_subnet(32)
        subnet_update_servers_iprange = virtual_network_iprange.next_subnet(32)
        subnet_identity_iprange = virtual_network_iprange.next_subnet(32)

        # Define NSGs
        nsg_monitoring = network.NetworkSecurityGroup(
            f"{self._name}_nsg_monitoring",
            network_security_group_name=f"{stack_name}-nsg-monitoring",
            resource_group_name=resource_group.name,
            security_rules=[],
            opts=child_opts,
        )
        nsg_update_servers = network.NetworkSecurityGroup(
            f"{self._name}_nsg_update_servers",
            network_security_group_name=f"{stack_name}-nsg-update-servers",
            resource_group_name=resource_group.name,
            security_rules=[],
            opts=child_opts,
        )
        nsg_identity = network.NetworkSecurityGroup(
            f"{self._name}_nsg_identity",
            network_security_group_name=f"{stack_name}-nsg-identity",
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
                ),  # allow routes to be created outside this definition
                child_opts,
            ),
        )

        # Define the virtual network and its subnets
        virtual_network = network.VirtualNetwork(
            f"{self._name}_virtual_network",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[str(virtual_network_iprange)],
            ),
            resource_group_name=resource_group.name,
            subnets=[],
            virtual_network_name=f"{stack_name}-vnet",
            opts=ResourceOptions.merge(
                ResourceOptions(
                    ignore_changes=["subnets"]
                ),  # allow subnets to be created outside this definition
                child_opts,
            ),
        )
        # AzureFirewall subnet
        subnet_firewall = network.Subnet(
            f"{self._name}_subnet_firewall",
            address_prefix=str(subnet_firewall_iprange),
            network_security_group=None,  # the firewall subnet must NOT have an NSG
            resource_group_name=resource_group.name,
            subnet_name="AzureFirewallSubnet",  # this name is forced by https://docs.microsoft.com/en-us/azure/firewall/tutorial-firewall-deploy-portal
            virtual_network_name=virtual_network.name,
            opts=child_opts,
        )
        # VPN gateway subnet
        subnet_vpn_gateway = network.Subnet(
            f"{self._name}_subnet_vpn_gateway",
            address_prefix=str(subnet_vpn_gateway_iprange),
            network_security_group=None,  # the VPN gateway subnet must NOT have an NSG
            resource_group_name=resource_group.name,
            subnet_name="GatewaySubnet",  # this name is forced by https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-vpn-faq#do-i-need-a-gatewaysubnet
            virtual_network_name=virtual_network.name,
            opts=child_opts,
        )
        # Monitoring subnet
        subnet_monitoring = network.Subnet(
            f"{self._name}_subnet_monitoring",
            address_prefix=str(subnet_monitoring_iprange),
            network_security_group=network.NetworkSecurityGroupArgs(
                id=nsg_monitoring.id
            ),
            resource_group_name=resource_group.name,
            route_table=network.RouteTableArgs(id=route_table.id),
            subnet_name="MonitoringSubnet",
            virtual_network_name=virtual_network.name,
            opts=child_opts,
        )
        # Update servers subnet
        subnet_update_servers = network.Subnet(
            f"{self._name}_subnet_update_servers",
            address_prefix=str(subnet_update_servers_iprange),
            network_security_group=network.NetworkSecurityGroupArgs(
                id=nsg_update_servers.id
            ),
            resource_group_name=resource_group.name,
            route_table=network.RouteTableArgs(id=route_table.id),
            subnet_name="UpdateServersSubnet",
            virtual_network_name=virtual_network.name,
            opts=child_opts,
        )
        # Identity subnet
        subnet_identity = network.Subnet(
            f"{self._name}_subnet_identity",
            address_prefix=str(subnet_identity_iprange),
            network_security_group=network.NetworkSecurityGroupArgs(id=nsg_identity.id),
            resource_group_name=resource_group.name,
            route_table=network.RouteTableArgs(id=route_table.id),
            subnet_name="IdentitySubnet",
            virtual_network_name=virtual_network.name,
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

        # Register outputs
        self.dns_zone_nameservers = dns_zone.name_servers
        self.domain_controller_private_ip = str(subnet_identity_iprange.available()[0])
        self.resource_group_name = Output.from_input(resource_group.name)
        self.route_table = route_table
        self.subnet_firewall = subnet_firewall
        self.subnet_identity = subnet_identity
        self.subnet_monitoring = subnet_monitoring
        self.subnet_update_servers = subnet_update_servers
        self.subnet_vpn_gateway = subnet_vpn_gateway
        self.virtual_network = virtual_network

        # Register exports
        self.exports = {
            "virtual_network_name": virtual_network.name,
        }
