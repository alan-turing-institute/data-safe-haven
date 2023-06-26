"""Pulumi component for SRE networking"""
# Standard library import
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

# Local imports
from data_safe_haven.external.interface import AzureIPv4Range
from data_safe_haven.helpers import alphanumeric, ordered_private_dns_zones
from ..common.enums import NetworkingPriorities


class SRENetworkingProps:
    """Properties for SRENetworkingComponent"""

    def __init__(
        self,
        location: Input[str],
        shm_fqdn: Input[str],
        shm_networking_resource_group_name: Input[str],
        shm_subnet_identity_servers_prefix: Input[str],
        shm_subnet_monitoring_prefix: Input[str],
        shm_subnet_update_servers_prefix: Input[str],
        shm_virtual_network_name: Input[str],
        shm_zone_name: Input[str],
        sre_index: Input[str],
    ):
        # Virtual network and subnet IP ranges
        self.vnet_iprange = Output.from_input(sre_index).apply(
            lambda index: AzureIPv4Range(f"10.{index}.0.0", f"10.{index}.255.255")
        )
        self.subnet_application_gateway_iprange = self.vnet_iprange.apply(
            lambda r: r.next_subnet(256)
        )
        self.subnet_guacamole_containers_iprange = self.vnet_iprange.apply(
            lambda r: r.next_subnet(128)
        )
        self.subnet_guacamole_database_iprange = self.vnet_iprange.apply(
            lambda r: r.next_subnet(128)
        )
        self.subnet_research_desktops_iprange = self.vnet_iprange.apply(
            lambda r: r.next_subnet(256)
        )
        self.subnet_private_data_iprange = self.vnet_iprange.apply(
            lambda r: r.next_subnet(16)
        )
        self.subnet_user_services_containers_iprange = self.vnet_iprange.apply(
            lambda r: r.next_subnet(16)
        )
        self.subnet_user_services_databases_iprange = self.vnet_iprange.apply(
            lambda r: r.next_subnet(16)
        )
        # Other variables
        self.location = location
        self.public_ip_range_users = "Internet"
        self.shm_fqdn = shm_fqdn
        self.shm_networking_resource_group_name = shm_networking_resource_group_name
        self.shm_subnet_identity_servers_prefix = shm_subnet_identity_servers_prefix
        self.shm_subnet_monitoring_prefix = shm_subnet_monitoring_prefix
        self.shm_subnet_update_servers_prefix = shm_subnet_update_servers_prefix
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
        super().__init__("dsh:sre:NetworkingComponent", name, {}, opts)
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
        subnet_private_data_prefix = props.subnet_private_data_iprange.apply(
            lambda r: str(r)
        )
        subnet_research_desktops_prefix = props.subnet_research_desktops_iprange.apply(
            lambda r: str(r)
        )
        subnet_user_services_containers_prefix = (
            props.subnet_user_services_containers_iprange.apply(lambda r: str(r))
        )
        subnet_user_services_databases_prefix = (
            props.subnet_user_services_databases_iprange.apply(lambda r: str(r))
        )

        # Define NSGs
        nsg_application_gateway = network.NetworkSecurityGroup(
            f"{self._name}_nsg_application_gateway",
            network_security_group_name=f"{stack_name}-nsg-application-gateway",
            resource_group_name=resource_group.name,
            security_rules=[
                network.SecurityRuleArgs(
                    access="Allow",
                    description="Allow inbound gateway management service traffic.",
                    destination_address_prefix="*",
                    destination_port_range="*",
                    direction="Inbound",
                    name="AllowGatewayManagerServiceInbound",
                    priority=NetworkingPriorities.AZURE_GATEWAY_MANAGER,
                    protocol="*",
                    source_address_prefix="GatewayManager",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access="Allow",
                    description="Allow inbound gateway management traffic over the internet.",
                    destination_address_prefix=subnet_application_gateway_prefix,
                    destination_port_range="65200-65535",
                    direction="Inbound",
                    name="AllowGatewayManagerInternetInbound",
                    priority=NetworkingPriorities.EXTERNAL_INTERNET,
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
                    priority=NetworkingPriorities.AUTHORISED_EXTERNAL_USER_IPS,
                    protocol="TCP",
                    source_address_prefix=props.public_ip_range_users,
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
        nsg_private_data = network.NetworkSecurityGroup(
            f"{self._name}_nsg_private_data",
            network_security_group_name=f"{stack_name}-nsg-private-data",
            resource_group_name=resource_group.name,
            opts=child_opts,
        )
        nsg_research_desktops = network.NetworkSecurityGroup(
            f"{self._name}_nsg_research_desktops",
            network_security_group_name=f"{stack_name}-nsg-research-desktops",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow connections to SRDs from remote desktop gateway.",
                    destination_address_prefix=subnet_research_desktops_prefix,
                    destination_port_ranges=["22", "3389"],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowRemoteDesktopGatewayInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_REMOTE_DESKTOP,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_guacamole_containers_prefix,
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
                    destination_address_prefix=str(props.shm_subnet_monitoring_prefix),
                    destination_port_ranges=["443"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowMonitoringToolsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_MONITORING_TOOLS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_research_desktops_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to private data endpoints.",
                    destination_address_prefix=subnet_private_data_prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowPrivateDataEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_PRIVATE_DATA,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_research_desktops_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to Linux update servers.",
                    destination_address_prefix=props.shm_subnet_update_servers_prefix,
                    destination_port_ranges=["8000"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowLinuxUpdatesOutbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_UPDATE_SERVERS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_research_desktops_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow LDAP client requests over UDP.",
                    destination_address_prefix=props.shm_subnet_identity_servers_prefix,
                    destination_port_ranges=["389", "636"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowLDAPClientUDPOutbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_LDAP_UDP,
                    protocol=network.SecurityRuleProtocol.UDP,
                    source_address_prefix=subnet_research_desktops_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow LDAP client requests over TCP (see https://devopstales.github.io/linux/pfsense-ad-join/ for details).",
                    destination_address_prefix=props.shm_subnet_identity_servers_prefix,
                    destination_port_ranges=["389", "636"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowLDAPClientTCPOutbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_LDAP_TCP,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_research_desktops_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to user services.",
                    destination_address_prefix=subnet_user_services_containers_prefix,
                    destination_port_ranges=["22", "80", "443"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowUserServicesContainersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_research_desktops_prefix,
                    source_port_range="*",
                ),
            ],
            opts=child_opts,
        )
        nsg_user_services_containers = network.NetworkSecurityGroup(
            f"{self._name}_nsg_user_services_containers",
            network_security_group_name=f"{stack_name}-nsg-user-services-containers",
            resource_group_name=resource_group.name,
            opts=child_opts,
        )
        nsg_user_services_databases = network.NetworkSecurityGroup(
            f"{self._name}_nsg_user_services_databases",
            network_security_group_name=f"{stack_name}-nsg-user-services-databases",
            resource_group_name=resource_group.name,
            opts=child_opts,
        )

        # Define the virtual network and its subnets
        subnet_application_gateway_name = "ApplicationGatewaySubnet"
        subnet_guacamole_containers_name = "GuacamoleContainersSubnet"
        subnet_guacamole_database_name = "GuacamoleDatabaseSubnet"
        subnet_private_data_name = "PrivateDataSubnet"
        subnet_research_desktops_name = "ResearchDesktopsSubnet"
        subnet_user_services_containers_name = "UserServicesContainersSubnet"
        subnet_user_services_databases_name = "UserServicesDatabasesSubnet"
        sre_virtual_network = network.VirtualNetwork(
            f"{self._name}_virtual_network",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[props.vnet_iprange.apply(lambda r: str(r))],
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
                # Private data
                network.SubnetArgs(
                    address_prefix=subnet_private_data_prefix,
                    name=subnet_private_data_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_private_data.id
                    ),
                    service_endpoints=[
                        network.ServiceEndpointPropertiesFormatArgs(
                            locations=[props.location],
                            service="Microsoft.Storage",
                        )
                    ],
                ),
                # Research desktops
                network.SubnetArgs(
                    address_prefix=subnet_research_desktops_prefix,
                    name=subnet_research_desktops_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_research_desktops.id
                    ),
                ),
                # User services containers
                network.SubnetArgs(
                    address_prefix=subnet_user_services_containers_prefix,
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name=subnet_user_services_containers_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_user_services_containers.id
                    ),
                ),
                # User services databases
                network.SubnetArgs(
                    address_prefix=subnet_user_services_databases_prefix,
                    name=subnet_user_services_databases_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_user_services_databases.id
                    ),
                ),
            ],
            virtual_network_name=f"{stack_name}-vnet",
            virtual_network_peerings=[],
            opts=ResourceOptions.merge(
                ResourceOptions(
                    ignore_changes=["virtual_network_peerings"]
                ),  # allow peering to SHM virtual network
                child_opts,
            ),
        )

        # Peer the SHM virtual network to the SRE virtual network
        shm_virtual_network = Output.all(
            resource_group_name=props.shm_networking_resource_group_name,
            virtual_network_name=props.shm_virtual_network_name,
        ).apply(
            lambda kwargs: network.get_virtual_network(
                resource_group_name=kwargs["resource_group_name"],
                virtual_network_name=kwargs["virtual_network_name"],
            )
        )
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
            allow_gateway_transit=True,
            remote_virtual_network=network.SubResourceArgs(id=sre_virtual_network.id),
            resource_group_name=props.shm_networking_resource_group_name,
            virtual_network_name=shm_virtual_network.name,
            virtual_network_peering_name=f"peer_shm_to_sre_{sre_name}",
            opts=child_opts,
        )

        # Link to SHM private DNS zones
        for private_link_domain in ordered_private_dns_zones():
            virtual_network_link = network.VirtualNetworkLink(
                f"{self._name}_private_zone_{private_link_domain}_vnet_link",
                location="Global",
                private_zone_name=f"privatelink.{private_link_domain}",
                registration_enabled=False,
                resource_group_name=props.shm_networking_resource_group_name,
                virtual_network=network.SubResourceArgs(id=sre_virtual_network.id),
                virtual_network_link_name=Output.concat(
                    "link-to-", sre_virtual_network.name
                ),
                opts=child_opts,
            )

        # Define SRE DNS zone
        shm_dns_zone = Output.all(
            resource_group_name=props.shm_networking_resource_group_name,
            zone_name=props.shm_zone_name,
        ).apply(
            lambda kwargs: network.get_zone(
                resource_group_name=kwargs["resource_group_name"],
                zone_name=kwargs["zone_name"],
            )
        )
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

        # Define SRE internal DNS zone
        sre_private_dns_zone = network.PrivateZone(
            f"{self._name}_private_zone",
            location="Global",
            private_zone_name=Output.concat("privatelink.", sre_fqdn),
            resource_group_name=resource_group.name,
            opts=child_opts,
        )
        virtual_network_link = network.VirtualNetworkLink(
            f"{self._name}_private_zone_vnet_link",
            location="Global",
            private_zone_name=sre_private_dns_zone.name,
            registration_enabled=False,
            resource_group_name=resource_group.name,
            virtual_network=network.SubResourceArgs(id=sre_virtual_network.id),
            virtual_network_link_name=Output.concat(
                "link-to-", sre_virtual_network.name
            ),
            opts=child_opts,
        )

        # Register outputs
        self.resource_group = resource_group
        self.shm_ns_record = shm_ns_record
        self.sre_fqdn = sre_dns_zone.name
        self.sre_private_dns_zone_id = sre_private_dns_zone.id
        self.sre_private_dns_zone = sre_private_dns_zone
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
        self.subnet_private_data = network.get_subnet_output(
            subnet_name=subnet_private_data_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_research_desktops = network.get_subnet_output(
            subnet_name=subnet_research_desktops_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_user_services_containers = network.get_subnet_output(
            subnet_name=subnet_user_services_containers_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_user_services_databases = network.get_subnet_output(
            subnet_name=subnet_user_services_databases_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.virtual_network = sre_virtual_network
