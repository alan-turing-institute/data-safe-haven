"""Pulumi component for SRE networking"""
# Standard library import
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

# Local imports
from data_safe_haven.external.interface import AzureIPv4Range
from data_safe_haven.helpers import alphanumeric


class SRENetworkingProps:
    """Properties for SRENetworkingComponent"""

    def __init__(
        self,
        location: Input[str],
        shm_fqdn: Input[str],
        shm_networking_resource_group_name: Input[str],
        shm_virtual_network_name: Input[str],
        shm_zone_name: Input[str],
        sre_index: Input[str],
    ):
        # Virtual network and subnet IP ranges
        self.virtual_network_iprange = Output.from_input(sre_index).apply(
            lambda index: AzureIPv4Range(f"10.{index}.0.0", f"10.{index}.255.255")
        )
        self.subnet_application_gateway_iprange = self.virtual_network_iprange.apply(
            lambda r: r.next_subnet(256)
        )
        self.subnet_guacamole_containers_iprange = self.virtual_network_iprange.apply(
            lambda r: r.next_subnet(128)
        )
        self.subnet_guacamole_database_iprange = self.virtual_network_iprange.apply(
            lambda r: r.next_subnet(128)
        )
        self.subnet_research_desktops_iprange = self.virtual_network_iprange.apply(
            lambda r: r.next_subnet(256)
        )
        # Other variables
        self.location = location
        self.shm_fqdn = shm_fqdn
        self.shm_networking_resource_group_name = shm_networking_resource_group_name
        self.shm_virtual_network_name = shm_virtual_network_name
        self.shm_zone_name = shm_zone_name


class SRENetworkingComponent(ComponentResource):
    """Deploy networking with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SRENetworkingProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:sre:SRENetworkingComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-networking",
            opts=child_opts,
        )

        # Set address prefixes from ranges
        subnet_application_gateway_prefix = (
            props.subnet_application_gateway_iprange.apply(lambda r: str(r))
        )
        subnet_guacamole_containers_prefix = (
            props.subnet_guacamole_containers_iprange.apply(lambda r: str(r))
        )
        subnet_guacamole_database_prefix = (
            props.subnet_guacamole_database_iprange.apply(lambda r: str(r))
        )
        subnet_research_desktops_prefix = props.subnet_research_desktops_iprange.apply(
            lambda r: str(r)
        )

        # Define NSGs
        nsg_application_gateway = network.NetworkSecurityGroup(
            f"{self._name}_nsg_application_gateway",
            network_security_group_name=f"{stack_name}-nsg-application-gateway",
            resource_group_name=resource_group.name,
            security_rules=[
                network.SecurityRuleArgs(
                    access="Allow",
                    description="Allow gateway management traffic by service tag.",
                    destination_address_prefix="*",
                    destination_port_range="*",
                    direction="Inbound",
                    name="AllowGatewayManagerServiceInbound",
                    priority=1000,
                    protocol="*",
                    source_address_prefix="GatewayManager",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access="Allow",
                    description="Allow gateway management traffic over the internet.",
                    destination_address_prefix=subnet_application_gateway_prefix,
                    destination_port_range="65200-65535",
                    direction="Inbound",
                    name="AllowGatewayManagerInternetInbound",
                    priority=1100,
                    protocol="*",
                    source_address_prefix="Internet",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access="Allow",
                    description="Allow inbound internet to Application Gateway.",
                    destination_address_prefix=subnet_application_gateway_prefix,
                    destination_port_ranges=["80", "443"],
                    direction="Inbound",
                    name="AllowInternetInbound",
                    priority=3000,
                    protocol="TCP",
                    source_address_prefix="Internet",
                    source_port_range="*",
                ),
            ],
            opts=child_opts,
        )
        nsg_guacamole_containers = network.NetworkSecurityGroup(
            f"{self._name}_nsg_guacamole_containers",
            network_security_group_name=f"{stack_name}-nsg-guacamole-containers",
            resource_group_name=resource_group.name,
            opts=child_opts,
        )
        nsg_guacamole_database = network.NetworkSecurityGroup(
            f"{self._name}_nsg_guacamole_database",
            network_security_group_name=f"{stack_name}-nsg-guacamole-database",
            resource_group_name=resource_group.name,
            opts=child_opts,
        )
        nsg_research_desktops = network.NetworkSecurityGroup(
            f"{self._name}_nsg_research_desktops",
            network_security_group_name=f"{stack_name}-nsg-research-desktops",
            resource_group_name=resource_group.name,
            security_rules=[
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow connections to SRDs from remote desktop gateway.",
                    destination_address_prefix="*",
                    destination_port_range="22",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowRemoteDesktopGatewayInbound",
                    priority=800,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_guacamole_containers_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow LDAP client requests over UDP.",
                    destination_address_prefix="*",
                    destination_port_ranges=["389", "636"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowLDAPClientUDPOutbound",
                    priority=1000,
                    protocol=network.SecurityRuleProtocol.UDP,
                    source_address_prefix=subnet_guacamole_containers_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow LDAP client requests over TCP (see https://devopstales.github.io/linux/pfsense-ad-join/ for details).",
                    destination_address_prefix="*",
                    destination_port_ranges=["389", "636"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowLDAPClientTCPOutbound",
                    priority=1100,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_guacamole_containers_prefix,
                    source_port_range="*",
                ),
            ],
            opts=child_opts,
        )

        # Define the virtual network and its subnets
        subnet_application_gateway_name = "ApplicationGatewaySubnet"
        subnet_guacamole_containers_name = "GuacamoleContainersSubnet"
        subnet_guacamole_database_name = "GuacamoleDatabaseSubnet"
        subnet_research_desktops_name = "ResearchDesktopsSubnet"
        sre_virtual_network = network.VirtualNetwork(
            f"{self._name}_virtual_network",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[
                    props.virtual_network_iprange.apply(lambda r: str(r))
                ],
            ),
            resource_group_name=resource_group.name,
            subnets=[  # Note that we define subnets inline to avoid creation order issues
                # Application gateway subnet
                network.SubnetArgs(
                    address_prefix=subnet_application_gateway_prefix,
                    name=subnet_application_gateway_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_application_gateway.id
                    ),
                ),
                # Guacamole containers
                network.SubnetArgs(
                    address_prefix=subnet_guacamole_containers_prefix,
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name=subnet_guacamole_containers_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_guacamole_containers.id
                    ),
                ),
                # Guacamole database
                network.SubnetArgs(
                    address_prefix=subnet_guacamole_database_prefix,
                    name=subnet_guacamole_database_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_guacamole_database.id
                    ),
                    private_endpoint_network_policies="Disabled",
                ),
                # Research desktops
                network.SubnetArgs(
                    address_prefix=subnet_research_desktops_prefix,
                    name=subnet_research_desktops_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_research_desktops.id
                    ),
                ),
            ],
            virtual_network_name=f"{stack_name}-vnet",
            opts=child_opts,
        )

        # Peer to the SHM virtual network
        shm_virtual_network = Output.all(
            resource_group_name=props.shm_networking_resource_group_name,
            virtual_network_name=props.shm_virtual_network_name,
        ).apply(lambda kwargs: network.get_virtual_network(**kwargs))
        peering_sre_to_shm = network.VirtualNetworkPeering(
            f"{self._name}_sre_to_shm_peering",
            remote_virtual_network=network.SubResourceArgs(id=shm_virtual_network.id),
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
            virtual_network_peering_name=f"peer_sre_{sre_name}_to_shm",
            opts=child_opts,
        )
        peering_shm_to_sre = network.VirtualNetworkPeering(
            f"{self._name}_shm_to_sre_peering",
            remote_virtual_network=network.SubResourceArgs(id=sre_virtual_network.id),
            resource_group_name=props.shm_networking_resource_group_name,
            virtual_network_name=shm_virtual_network.name,
            virtual_network_peering_name=f"peer_shm_to_sre_{sre_name}",
            opts=child_opts,
        )

        # Define SRE DNS zone
        shm_dns_zone = Output.all(
            resource_group_name=props.shm_networking_resource_group_name,
            zone_name=props.shm_zone_name,
        ).apply(lambda kwargs: network.get_zone(**kwargs))
        sre_subdomain = alphanumeric(sre_name)
        sre_fqdn = Output.from_input(props.shm_fqdn).apply(
            lambda parent: f"{sre_subdomain}.{parent}"
        )
        sre_dns_zone = network.Zone(
            f"{self._name}_dns_zone",
            location="Global",
            resource_group_name=resource_group.name,
            zone_name=sre_fqdn,
            zone_type=network.ZoneType.PUBLIC,
            opts=child_opts,
        )
        shm_ns_record = network.RecordSet(
            f"{self._name}_ns_record",
            ns_records=sre_dns_zone.name_servers.apply(
                lambda servers: [network.NsRecordArgs(nsdname=ns) for ns in servers]
            ),
            record_type="NS",
            relative_record_set_name=sre_subdomain,
            resource_group_name=props.shm_networking_resource_group_name,
            ttl=3600,
            zone_name=shm_dns_zone.name,
            opts=child_opts,
        )
        sre_caa_record = network.RecordSet(
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
            zone_name=sre_dns_zone.name,
            opts=child_opts,
        )

        # Register outputs
        self.resource_group = resource_group
        self.sre_fqdn = sre_dns_zone.name
        self.subnet_application_gateway = network.get_subnet_output(
            subnet_name=subnet_application_gateway_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_guacamole_containers = network.get_subnet_output(
            subnet_name=subnet_guacamole_containers_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_guacamole_database = network.get_subnet_output(
            subnet_name=subnet_guacamole_database_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_research_desktops = network.get_subnet_output(
            subnet_name=subnet_research_desktops_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.virtual_network = sre_virtual_network
