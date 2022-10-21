"""Pulumi component for SRE networking"""
# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

# Local imports
from data_safe_haven.helpers import AzureIPv4Range, alphanumeric


class SRENetworkingProps:
    """Properties for SRENetworkingComponent"""

    def __init__(
        self,
        location: Input[str],
        shm_fqdn: Input[str],
        shm_zone_resource_group_name: Input[str],
        shm_zone_name: Input[str],
        sre_index: Input[str],
    ):
        self.location = location
        # VNet
        self.vnet_ip_range = Output.from_input(sre_index).apply(
            lambda index: AzureIPv4Range(f"10.{index}.0.0", f"10.{index}.255.255")
        )
        self.vnet_cidr = self.vnet_ip_range.apply(lambda ip_range: str(ip_range))
        # Application gateway subnet
        self.application_gateway_ip_range = Output.from_input(sre_index).apply(
            lambda index: AzureIPv4Range(f"10.{index}.0.0", f"10.{index}.0.255")
        )
        self.application_gateway_cidr = self.application_gateway_ip_range.apply(
            lambda ip_range: str(ip_range)
        )
        self.application_gateway_subnet_name = "ApplicationGatewaySubnet"
        # Guacamole containers subnet
        self.guacamole_containers_ip_range = Output.from_input(sre_index).apply(
            lambda index: AzureIPv4Range(f"10.{index}.1.0", f"10.{index}.1.127")
        )
        self.guacamole_containers_cidr = self.guacamole_containers_ip_range.apply(
            lambda ip_range: str(ip_range)
        )
        self.guacamole_containers_subnet_name = "GuacamoleContainersSubnet"
        # Guacamole database server subnet
        self.guacamole_database_ip_range = Output.from_input(sre_index).apply(
            lambda index: AzureIPv4Range(f"10.{index}.1.128", f"10.{index}.1.255")
        )
        self.guacamole_database_cidr = self.guacamole_database_ip_range.apply(
            lambda ip_range: str(ip_range)
        )
        self.guacamole_database_subnet_name = "GuacamoleDatabaseSubnet"
        # Secure research desktop subnet
        self.srds_ip_range = Output.from_input(sre_index).apply(
            lambda index: AzureIPv4Range(f"10.{index}.2.0", f"10.{index}.2.255")
        )
        self.srds_cidr = self.srds_ip_range.apply(lambda ip_range: str(ip_range))
        self.srds_subnet_name = "SecureResearchDesktopSubnet"
        self.shm_fqdn = shm_fqdn
        self.shm_zone_resource_group_name = shm_zone_resource_group_name
        self.shm_zone_name = shm_zone_name


class SRENetworkingComponent(ComponentResource):
    """Deploy networking with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SRENetworkingProps,
        opts: ResourceOptions = None,
    ):
        super().__init__("dsh:sre:SRENetworkingComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"rg-{stack_name}-networking",
        )

        # Define NSGs
        nsg_application_gateway = network.NetworkSecurityGroup(
            f"{self._name}_nsg_application_gateway",
            network_security_group_name=f"nsg-{stack_name}-application-gateway",
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
                    destination_address_prefix=props.application_gateway_cidr,
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
                    destination_address_prefix=props.application_gateway_cidr,
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
        nsg_guacamole = network.NetworkSecurityGroup(
            f"{self._name}_nsg_guacamole",
            network_security_group_name=f"nsg-{stack_name}-guacamole",
            resource_group_name=resource_group.name,
            opts=child_opts,
        )
        nsg_secure_research_desktop = network.NetworkSecurityGroup(
            f"{self._name}_nsg_secure_research_desktop",
            network_security_group_name=f"nsg-{stack_name}-secure-research-desktop",
            resource_group_name=resource_group.name,
            security_rules=[
                network.SecurityRuleArgs(
                    access="Allow",
                    description="Allow inbound SSH from Guacamole.",
                    destination_address_prefix="*",
                    destination_port_range="22",
                    direction="Inbound",
                    name="AllowGuacamoleSSHInbound",
                    priority=1000,
                    protocol="*",
                    source_address_prefix=props.guacamole_containers_cidr,
                    source_port_range="*",
                ),
            ],
            opts=child_opts,
        )

        # Define the virtual network with inline subnets
        virtual_network = network.VirtualNetwork(
            f"{self._name}_virtual_network",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[props.vnet_cidr],
            ),
            resource_group_name=resource_group.name,
            subnets=[  # Note that we need to define subnets inline or they will be destroyed/recreated on a new run
                network.SubnetArgs(
                    address_prefix=props.application_gateway_cidr,
                    name=props.application_gateway_subnet_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_application_gateway.id
                    ),
                ),
                network.SubnetArgs(
                    address_prefix=props.guacamole_containers_cidr,
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name=props.guacamole_containers_subnet_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_guacamole.id
                    ),
                ),
                network.SubnetArgs(
                    address_prefix=props.guacamole_database_cidr,
                    name=props.guacamole_database_subnet_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_guacamole.id
                    ),
                    private_endpoint_network_policies="Disabled",
                ),
                network.SubnetArgs(
                    address_prefix=props.srds_cidr,
                    name=props.srds_subnet_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_secure_research_desktop.id
                    ),
                ),
            ],
            virtual_network_name=f"vnet-{stack_name}",
            opts=child_opts,
        )

        # Define public IP address
        public_ip = network.PublicIPAddress(
            f"{self._name}_public_ip",
            public_ip_address_name=f"{stack_name}-public-ip",
            public_ip_allocation_method="Static",
            resource_group_name=resource_group.name,
            sku=network.PublicIPAddressSkuArgs(name="Standard"),
            opts=child_opts,
        )

        # Define SRE DNS zone
        shm_dns_zone = network.get_zone(
            resource_group_name=props.shm_zone_resource_group_name,
            zone_name=props.shm_zone_name,
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
            zone_type="Public",
        )
        shm_ns_record = network.RecordSet(
            f"{self._name}_ns_record",
            ns_records=sre_dns_zone.name_servers.apply(
                lambda servers: [network.NsRecordArgs(nsdname=ns) for ns in servers]
            ),
            record_type="NS",
            relative_record_set_name=sre_subdomain,
            resource_group_name=props.shm_zone_resource_group_name,
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
        sre_a_record = network.RecordSet(
            f"{self._name}_a_record",
            a_records=[
                network.ARecordArgs(
                    ipv4_address=public_ip.ip_address,
                )
            ],
            record_type="A",
            relative_record_set_name="@",
            resource_group_name=resource_group.name,
            ttl=30,
            zone_name=sre_dns_zone.name,
            opts=child_opts,
        )

        # Extract useful variables
        ip_address_guacamole_container = props.guacamole_containers_ip_range.apply(
            lambda ip_range: str(ip_range.available()[0])
        )
        ip_address_guacamole_database = props.guacamole_database_ip_range.apply(
            lambda ip_range: str(ip_range.available()[0])
        )

        # Register outputs
        self.application_gateway = {
            "subnet_name": props.application_gateway_subnet_name,
        }
        self.guacamole_containers = {
            "ip_address": ip_address_guacamole_container,
            "subnet_name": props.guacamole_containers_subnet_name,
        }
        self.guacamole_database = {
            "ip_address": ip_address_guacamole_database,
            "subnet_name": props.guacamole_database_subnet_name,
        }
        self.public_ip_id = public_ip.id
        self.resource_group_name = resource_group.name
        self.sre_fqdn = sre_dns_zone.name
        self.virtual_network = virtual_network
