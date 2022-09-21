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
        self.ip_network_vnet = Output.from_input(sre_index).apply(
            lambda index: AzureIPv4Range(f"10.{index}.0.0", f"10.{index}.255.255")
        )
        self.ip_network_vnet_cidr = self.ip_network_vnet.apply(
            lambda ip_range: str(ip_range)
        )
        # Application gateway subnet
        self.ip_network_application_gateway = Output.from_input(sre_index).apply(
            lambda index: AzureIPv4Range(f"10.{index}.0.0", f"10.{index}.0.255")
        )
        self.cidr_application_gateway = self.ip_network_application_gateway.apply(
            lambda ip_range: str(ip_range)
        )
        # Guacamole containers subnet
        self.ip_network_guacamole_containers = Output.from_input(sre_index).apply(
            lambda index: AzureIPv4Range(f"10.{index}.1.0", f"10.{index}.1.127")
        )
        self.cidr_guacamole_containers = self.ip_network_guacamole_containers.apply(
            lambda ip_range: str(ip_range)
        )
        # Guacamole PostgreSQL server subnet
        self.ip_network_guacamole_postgresql = Output.from_input(sre_index).apply(
            lambda index: AzureIPv4Range(f"10.{index}.1.128", f"10.{index}.1.255")
        )
        self.cidr_guacamole_postgresql = self.ip_network_guacamole_postgresql.apply(
            lambda ip_range: str(ip_range)
        )
        # Secure research desktop subnet
        self.ip_network_srds = Output.from_input(sre_index).apply(
            lambda index: AzureIPv4Range(f"10.{index}.2.0", f"10.{index}.2.255")
        )
        self.cidr_srds = self.ip_network_srds.apply(lambda ip_range: str(ip_range))


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
                    destination_address_prefix=props.cidr_application_gateway,
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
                    destination_address_prefix=props.cidr_application_gateway,
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
                    source_address_prefix=props.cidr_guacamole_containers,
                    source_port_range="*",
                ),
            ],
            opts=child_opts,
        )

        # Define the virtual network with inline subnets
        vnet = network.VirtualNetwork(
            "vnet",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[props.ip_network_vnet_cidr],
            ),
            resource_group_name=props.resource_group_name,
            subnets=[  # Note that we need to define subnets inline or they will be destroyed/recreated on a new run
                network.SubnetArgs(
                    address_prefix=props.cidr_application_gateway,
                    name="ApplicationGatewaySubnet",
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_application_gateway.id
                    ),
                ),
                network.SubnetArgs(
                    address_prefix=props.cidr_guacamole_postgresql,
                    name="GuacamoleDatabaseSubnet",
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_guacamole.id
                    ),
                    private_endpoint_network_policies="Disabled",
                ),
                network.SubnetArgs(
                    address_prefix=props.cidr_guacamole_containers,
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name="GuacamoleContainersSubnet",
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_guacamole.id
                    ),
                ),
                network.SubnetArgs(
                    address_prefix=props.cidr_srds,
                    name="SecureResearchDesktopSubnet",
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_secure_research_desktop.id
                    ),
                ),
            ],
            virtual_network_name=f"vnet-{self._name}",
            opts=child_opts,
        )

        # Register outputs
        # self.ip_address_guacamole_container = (
        #     props.ip_network_guacamole_containers.apply(
        #         lambda ip_range: str(ip_range.available()[0])
        #     )
        # )
        # self.ip_address_guacamole_postgresql = (
        #     props.ip_network_guacamole_postgresql.apply(
        #         lambda ip_range: str(ip_range.available()[0])
        #     )
        # )
        # self.ip_addresses_srd = props.ip_network_srds.apply(
        #     lambda ip_range: [str(ip) for ip in ip_range.available()]
        # )
        self.resource_group_name = Output.from_input(props.resource_group_name)
        self.vnet = vnet
