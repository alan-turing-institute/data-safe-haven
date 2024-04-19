"""Pulumi component for SHM networking"""

from collections.abc import Mapping, Sequence

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

from data_safe_haven.external import AzureIPv4Range
from data_safe_haven.functions import ordered_private_dns_zones
from data_safe_haven.infrastructure.common import NetworkingPriorities, Ports


class SHMNetworkingProps:
    """Properties for SHMNetworkingComponent"""

    def __init__(
        self,
        admin_ip_addresses: Input[Sequence[str]],
        fqdn: Input[str],
        location: Input[str],
        record_domain_verification: Input[str],
    ) -> None:
        # Virtual network and subnet IP ranges
        self.vnet_iprange = AzureIPv4Range("10.0.0.0", "10.0.255.255")
        # Bastion subnet must be at least /26 in size (64 addresses)
        self.subnet_bastion_iprange = self.vnet_iprange.next_subnet(64)
        # Firewall subnet must be at least /26 in size (64 addresses)
        self.subnet_firewall_iprange = self.vnet_iprange.next_subnet(64)
        self.subnet_identity_servers_iprange = self.vnet_iprange.next_subnet(8)
        # Monitoring subnet needs 2 IP addresses for automation and 13 for log analytics
        self.subnet_monitoring_iprange = self.vnet_iprange.next_subnet(32)
        self.subnet_update_servers_iprange = self.vnet_iprange.next_subnet(8)
        # Other variables
        self.admin_ip_addresses = admin_ip_addresses
        self.fqdn = fqdn
        self.location = location
        self.record_domain_verification = record_domain_verification


class SHMNetworkingComponent(ComponentResource):
    """Deploy SHM networking with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SHMNetworkingProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:shm:NetworkingComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-networking",
            opts=child_opts,
            tags=child_tags,
        )

        # Define NSGs
        nsg_bastion = network.NetworkSecurityGroup(
            f"{self._name}_nsg_bastion",
            network_security_group_name=f"{stack_name}-nsg-bastion",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound https connections from admins connecting from approved IP addresses.",
                    destination_address_prefix="*",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
                    destination_port_ranges=[Ports.HTTPS],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowAdminHttpsInbound",
                    priority=NetworkingPriorities.AUTHORISED_EXTERNAL_ADMIN_IPS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefixes=props.admin_ip_addresses,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound gateway management service traffic.",
                    destination_address_prefix="*",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
                    destination_port_ranges=[Ports.HTTPS],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowGatewayManagerServiceInbound",
                    priority=NetworkingPriorities.AZURE_GATEWAY_MANAGER,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix="GatewayManager",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound load balancer service traffic.",
                    destination_address_prefix="*",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
                    destination_port_ranges=[Ports.HTTPS],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowLoadBalancerServiceInbound",
                    priority=NetworkingPriorities.AZURE_LOAD_BALANCER,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix="AzureLoadBalancer",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound internal bastion host communication.",
                    destination_address_prefix="VirtualNetwork",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
                    destination_port_ranges=[
                        Ports.AZURE_BASTION_1,
                        Ports.AZURE_BASTION_2,
                    ],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowBastionHostInbound",
                    priority=NetworkingPriorities.INTERNAL_SELF,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="VirtualNetwork",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
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
                    description="Allow outbound connections to DSH VMs.",
                    destination_address_prefix="VirtualNetwork",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
                    destination_port_ranges=[Ports.SSH, Ports.RDP],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowRdpOutbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_BASTION,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to Azure public endpoints.",
                    destination_address_prefix="AzureCloud",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
                    destination_port_ranges=[Ports.HTTPS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowAzureCloudOutbound",
                    priority=NetworkingPriorities.AZURE_CLOUD,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix="*",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound internal bastion host communication.",
                    destination_address_prefix="VirtualNetwork",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
                    destination_port_ranges=[
                        Ports.AZURE_BASTION_1,
                        Ports.AZURE_BASTION_2,
                    ],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowBastionHostOutbound",
                    priority=NetworkingPriorities.INTERNAL_SELF,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="VirtualNetwork",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections for session and certificate validation.",
                    destination_address_prefix="Internet",
                    destination_port_ranges=[Ports.HTTP],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowCertificateValidationOutbound",
                    priority=NetworkingPriorities.EXTERNAL_INTERNET,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",  # required by https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
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
            tags=child_tags,
        )
        nsg_identity_servers = network.NetworkSecurityGroup(
            f"{self._name}_nsg_identity",
            network_security_group_name=f"{stack_name}-nsg-identity",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound LDAP to domain controllers.",
                    destination_address_prefix=str(
                        props.subnet_identity_servers_iprange
                    ),
                    destination_port_ranges=[Ports.LDAP, Ports.LDAPS],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowLDAPClientUDPInbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_LDAP_UDP,
                    protocol=network.SecurityRuleProtocol.UDP,
                    source_address_prefix="VirtualNetwork",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound LDAP to domain controllers.",
                    destination_address_prefix=str(
                        props.subnet_identity_servers_iprange
                    ),
                    destination_port_ranges=[Ports.LDAP, Ports.LDAPS],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowLDAPClientTCPInbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_LDAP_TCP,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix="VirtualNetwork",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound RDP connections from admins using AzureBastion.",
                    destination_address_prefix=str(
                        props.subnet_identity_servers_iprange
                    ),
                    destination_port_ranges=[Ports.RDP],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowBastionAdminsInbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_BASTION,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=str(props.subnet_bastion_iprange),
                    source_port_range="*",
                ),
            ],
            opts=child_opts,
            tags=child_tags,
        )
        nsg_monitoring = network.NetworkSecurityGroup(
            f"{self._name}_nsg_monitoring",
            network_security_group_name=f"{stack_name}-nsg-monitoring",
            resource_group_name=resource_group.name,
            security_rules=[],
            opts=child_opts,
            tags=child_tags,
        )
        nsg_update_servers = network.NetworkSecurityGroup(
            f"{self._name}_nsg_update_servers",
            network_security_group_name=f"{stack_name}-nsg-update-servers",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from the local virtual network.",
                    destination_address_prefix=str(props.subnet_update_servers_iprange),
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowVirtualNetworkInbound",
                    priority=NetworkingPriorities.INTERNAL_SELF,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="VirtualNetwork",
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
                    description="Allow outbound connections to local monitoring tools.",
                    destination_address_prefix=str(props.subnet_monitoring_iprange),
                    destination_port_ranges=[Ports.HTTPS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowMonitoringToolsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_MONITORING_TOOLS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=str(props.subnet_update_servers_iprange),
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to Linux update servers.",
                    destination_address_prefix="Internet",
                    destination_port_ranges=[Ports.HTTP, Ports.HTTPS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowLinuxUpdatesOutbound",
                    priority=NetworkingPriorities.EXTERNAL_LINUX_UPDATES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=str(props.subnet_update_servers_iprange),
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
            tags=child_tags,
        )

        # Define route table
        route_table = network.RouteTable(
            f"{self._name}_route_table",
            location=props.location,
            resource_group_name=resource_group.name,
            route_table_name=f"{stack_name}-route",
            routes=[],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=["routes"]
                ),  # allow routes to be created outside this definition
            ),
            tags=child_tags,
        )

        # Define the virtual network and its subnets
        subnet_firewall_name = "AzureFirewallSubnet"  # this name is forced by https://docs.microsoft.com/en-us/azure/firewall/tutorial-firewall-deploy-portal
        subnet_bastion_name = "AzureBastionSubnet"  # this name is forced by https://learn.microsoft.com/en-us/azure/bastion/configuration-settings#subnet
        subnet_identity_servers_name = "IdentityServersSubnet"
        subnet_monitoring_name = "MonitoringSubnet"
        subnet_update_servers_name = "UpdateServersSubnet"
        virtual_network = network.VirtualNetwork(
            f"{self._name}_virtual_network",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[str(props.vnet_iprange)],
            ),
            resource_group_name=resource_group.name,
            subnets=[  # Note that we define subnets inline to avoid creation order issues
                # Bastion subnet
                network.SubnetArgs(
                    address_prefix=str(props.subnet_bastion_iprange),
                    name=subnet_bastion_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_bastion.id
                    ),
                    route_table=None,  # the bastion subnet must NOT be attached to the route table
                ),
                # AzureFirewall subnet
                network.SubnetArgs(
                    address_prefix=str(props.subnet_firewall_iprange),
                    name=subnet_firewall_name,
                    network_security_group=None,  # the firewall subnet must NOT have an NSG
                    route_table=None,  # the firewall subnet must NOT be attached to the route table
                ),
                # Identity servers subnet
                network.SubnetArgs(
                    address_prefix=str(props.subnet_identity_servers_iprange),
                    name=subnet_identity_servers_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_identity_servers.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # Monitoring subnet
                network.SubnetArgs(
                    address_prefix=str(props.subnet_monitoring_iprange),
                    name=subnet_monitoring_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_monitoring.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # Update servers subnet
                network.SubnetArgs(
                    address_prefix=str(props.subnet_update_servers_iprange),
                    name=subnet_update_servers_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_update_servers.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
            ],
            virtual_network_name=f"{stack_name}-vnet",
            virtual_network_peerings=[],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=[
                        "subnets",
                        "virtual_network_peerings",
                    ]
                ),  # allow SRE virtual networks to peer to this
            ),
            tags=child_tags,
        )

        # Define SHM DNS zone
        dns_zone = network.Zone(
            f"{self._name}_dns_zone",
            location="Global",
            resource_group_name=resource_group.name,
            zone_name=props.fqdn,
            zone_type=network.ZoneType.PUBLIC,
            opts=child_opts,
            tags=child_tags,
        )
        network.RecordSet(
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
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=dns_zone)),
        )
        network.RecordSet(
            f"{self._name}_domain_verification_record",
            record_type="TXT",
            relative_record_set_name="@",
            resource_group_name=resource_group.name,
            ttl=3600,
            txt_records=[
                network.TxtRecordArgs(value=[props.record_domain_verification])
            ],
            zone_name=dns_zone.name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=dns_zone)),
        )

        # Set up private link domains
        private_zone_ids: list[Output[str]] = []
        for private_link_domain in ordered_private_dns_zones():
            private_zone = network.PrivateZone(
                f"{self._name}_private_zone_{private_link_domain}",
                location="Global",
                private_zone_name=f"privatelink.{private_link_domain}",
                resource_group_name=resource_group.name,
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=dns_zone)
                ),
                tags=child_tags,
            )
            network.VirtualNetworkLink(
                f"{self._name}_private_zone_{private_link_domain}_vnet_link",
                location="Global",
                private_zone_name=private_zone.name,
                registration_enabled=False,
                resource_group_name=resource_group.name,
                virtual_network=network.SubResourceArgs(id=virtual_network.id),
                virtual_network_link_name=Output.concat(
                    "link-to-", virtual_network.name
                ),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=private_zone)
                ),
                tags=child_tags,
            )
            private_zone_ids.append(
                private_zone.id.apply(
                    lambda zone_id: "".join(zone_id.partition("privatelink.")[:-1])
                )
            )

        # Register outputs
        self.dns_zone = dns_zone
        self.domain_controller_private_ip = str(
            props.subnet_identity_servers_iprange.available()[0]
        )
        self.private_dns_zone_base_id = private_zone_ids[0]
        self.resource_group_name = Output.from_input(resource_group.name)
        self.route_table = route_table
        self.subnet_bastion = network.get_subnet_output(
            subnet_name=subnet_bastion_name,
            resource_group_name=resource_group.name,
            virtual_network_name=virtual_network.name,
        )
        self.subnet_firewall = network.get_subnet_output(
            subnet_name=subnet_firewall_name,
            resource_group_name=resource_group.name,
            virtual_network_name=virtual_network.name,
        )
        self.subnet_identity_servers = network.get_subnet_output(
            subnet_name=subnet_identity_servers_name,
            resource_group_name=resource_group.name,
            virtual_network_name=virtual_network.name,
        )
        self.subnet_monitoring = network.get_subnet_output(
            subnet_name=subnet_monitoring_name,
            resource_group_name=resource_group.name,
            virtual_network_name=virtual_network.name,
        )
        self.subnet_update_servers = network.get_subnet_output(
            subnet_name=subnet_update_servers_name,
            resource_group_name=resource_group.name,
            virtual_network_name=virtual_network.name,
        )
        self.virtual_network = virtual_network

        # Register exports
        self.exports = {
            "fqdn_nameservers": self.dns_zone.name_servers,
            "private_dns_zone_base_id": self.private_dns_zone_base_id,
            "resource_group_name": resource_group.name,
            "subnet_bastion_prefix": self.subnet_bastion.apply(
                lambda s: str(s.address_prefix) if s.address_prefix else ""
            ),
            "subnet_identity_servers_prefix": self.subnet_identity_servers.apply(
                lambda s: str(s.address_prefix) if s.address_prefix else ""
            ),
            "subnet_monitoring_prefix": self.subnet_monitoring.apply(
                lambda s: str(s.address_prefix) if s.address_prefix else ""
            ),
            "subnet_update_servers_prefix": self.subnet_update_servers.apply(
                lambda s: str(s.address_prefix) if s.address_prefix else ""
            ),
            "virtual_network_name": virtual_network.name,
        }
