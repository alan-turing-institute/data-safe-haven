# Standard library imports
import ipaddress
from typing import Optional, Sequence

# Third party imports
from pulumi import ComponentResource, Input, ResourceOptions, Output
from pulumi_azure_native import network

# Local imports
from data_safe_haven.helpers import AzureIPv4Range


class SRENetworkingProps:
    """Properties for SRENetworkingComponent"""

    def __init__(
        self,
        resource_group_name: Input[str],
        sre_index: Input[str],
    ):
        self.resource_group_name = resource_group_name
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


class SRENetworkingComponent(ComponentResource):
    """Deploy networking with Pulumi"""

    def __init__(
        self, name: str, props: SRENetworkingProps, opts: ResourceOptions = None
    ):
        super().__init__("dsh:network:SRENetworkingComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Define NSGs
        nsg_application_gateway = network.NetworkSecurityGroup(
            "nsg_application_gateway",
            network_security_group_name=f"nsg-{self._name}-application-gateway",
            resource_group_name=props.resource_group_name,
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
            "nsg_guacamole",
            network_security_group_name=f"nsg-{self._name}-guacamole",
            resource_group_name=props.resource_group_name,
            opts=child_opts,
        )
        nsg_secure_research_desktop = network.NetworkSecurityGroup(
            "nsg_secure_research_desktop",
            network_security_group_name=f"nsg-{self._name}-secure-research-desktop",
            resource_group_name=props.resource_group_name,
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
        vnet = network.VirtualNetwork(
            "vnet",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[props.vnet_cidr],
            ),
            resource_group_name=props.resource_group_name,
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
            virtual_network_name=f"vnet-{self._name}",
            opts=child_opts,
        )

        # Register outputs
        ip_address_guacamole_container = props.guacamole_containers_ip_range.apply(
            lambda ip_range: str(ip_range.available()[0])
        )
        ip_address_guacamole_database = props.guacamole_database_ip_range.apply(
            lambda ip_range: str(ip_range.available()[0])
        )
        self.guacamole_containers = {
            "ip_address": ip_address_guacamole_container,
            "subnet_name": props.guacamole_containers_subnet_name,
        }
        self.guacamole_database = {
            "ip_address": ip_address_guacamole_database,
            "subnet_name": props.guacamole_database_subnet_name,
        }
        # self.ip_addresses_srd = props.srds_ip_range.apply(
        #     lambda ip_range: [str(ip) for ip in ip_range.available()]
        # )
        self.resource_group_name = Output.from_input(props.resource_group_name)
        self.vnet = vnet
