# Standard library imports
import ipaddress
from typing import Optional, Sequence

# Third party imports
from pulumi import ComponentResource, Input, ResourceOptions, Output
from pulumi_azure_native import network


class AzureIPv4Range(ipaddress.IPv4Network):
    """Azure-aware IPv4 address range"""

    def __init__(self, ip_address_first: str, ip_address_last: str):
        networks = list(
            ipaddress.summarize_address_range(
                ipaddress.ip_address(ip_address_first),
                ipaddress.ip_address(ip_address_last),
            )
        )
        if len(networks) != 1:
            raise ValueError(
                f"{ip_address_first}-{ip_address_last} cannot be expressed as a single network range."
            )
        super().__init__(networks[0])

    def available(self):
        """Azure reserves x.x.x.1 for the default gateway and (x.x.x.2, x.x.x.3) to map Azure DNS IPs."""
        return list(self.hosts())[3:]


class NetworkProps:
    """Properties for NetworkComponent"""

    def __init__(
        self,
        resource_group_name: Input[str],
        ip_range_vnet: Optional[Input[Sequence[str]]] = [
            "10.0.0.0",
            "10.0.255.255",
        ],
        ip_range_application_gateway: Optional[Input[Sequence[str]]] = [
            "10.0.0.0",
            "10.0.0.255",
        ],
        ip_range_authelia: Optional[Input[Sequence[str]]] = [
            "10.0.1.0",
            "10.0.1.127",
        ],
        ip_range_openldap: Optional[Input[Sequence[str]]] = [
            "10.0.1.128",
            "10.0.1.255",
        ],
        ip_range_guacamole_postgresql: Optional[Input[Sequence[str]]] = [
            "10.0.2.0",
            "10.0.2.127",
        ],
        ip_range_guacamole_containers: Optional[Input[Sequence[str]]] = [
            "10.0.2.128",
            "10.0.2.255",
        ],
        ip_range_secure_research_desktop: Optional[Input[Sequence[str]]] = [
            "10.0.3.0",
            "10.0.3.255",
        ],
    ):
        self.ip_range_vnet = ip_range_vnet
        self.ip_range_application_gateway = ip_range_application_gateway
        self.ip_range_authelia = ip_range_authelia
        self.ip_range_openldap = ip_range_openldap
        self.ip_range_guacamole_postgresql = ip_range_guacamole_postgresql
        self.ip_range_guacamole_containers = ip_range_guacamole_containers
        self.ip_range_secure_research_desktop = ip_range_secure_research_desktop
        self.resource_group_name = resource_group_name


class NetworkComponent(ComponentResource):
    """Deploy networking with Pulumi"""

    def __init__(self, name: str, props: NetworkProps, opts: ResourceOptions = None):
        super().__init__("dsh:network:NetworkComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Set address prefixes from ranges
        ip_network_vnet = AzureIPv4Range(*props.ip_range_vnet)
        ip_network_application_gateway = AzureIPv4Range(
            *props.ip_range_application_gateway
        )
        ip_network_authelia = AzureIPv4Range(*props.ip_range_authelia)
        ip_network_openldap = AzureIPv4Range(*props.ip_range_openldap)
        ip_network_guacamole_postgresql = AzureIPv4Range(
            *props.ip_range_guacamole_postgresql
        )
        ip_network_guacamole_containers = AzureIPv4Range(
            *props.ip_range_guacamole_containers
        )
        ip_network_secure_research_desktop = AzureIPv4Range(
            *props.ip_range_secure_research_desktop
        )

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
                    destination_address_prefix=str(ip_network_application_gateway),
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
                    destination_address_prefix=str(ip_network_application_gateway),
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
        nsg_authelia = network.NetworkSecurityGroup(
            "nsg_authelia",
            network_security_group_name=f"nsg-{self._name}-authelia",
            resource_group_name=props.resource_group_name,
            opts=child_opts,
        )
        nsg_openldap = network.NetworkSecurityGroup(
            "nsg_openldap",
            network_security_group_name=f"nsg-{self._name}-openldap",
            resource_group_name=props.resource_group_name,
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
                    source_address_prefix=str(ip_network_guacamole_containers),
                    source_port_range="*",
                ),
            ],
            opts=child_opts,
        )

        # Define the virtual network with inline subnets
        vnet = network.VirtualNetwork(
            "vnet",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[str(ip_network_vnet)],
            ),
            resource_group_name=props.resource_group_name,
            subnets=[  # Note that we need to define subnets inline or they will be destroyed/recreated on a new run
                network.SubnetArgs(
                    address_prefix=str(ip_network_application_gateway),
                    name="ApplicationGatewaySubnet",
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_application_gateway.id
                    ),
                ),
                network.SubnetArgs(
                    address_prefix=str(ip_network_authelia),
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name="AutheliaSubnet",
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_authelia.id
                    ),
                ),
                network.SubnetArgs(
                    address_prefix=str(ip_network_openldap),
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name="OpenLDAPSubnet",
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_openldap.id
                    ),
                ),
                network.SubnetArgs(
                    address_prefix=str(ip_network_guacamole_postgresql),
                    name="GuacamoleDatabaseSubnet",
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_guacamole.id
                    ),
                    private_endpoint_network_policies="Disabled",
                ),
                network.SubnetArgs(
                    address_prefix=str(ip_network_guacamole_containers),
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
                    address_prefix=str(ip_network_secure_research_desktop),
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
        self.ip_address_openldap = Output.from_input(
            str(ip_network_openldap.available()[0])
        )
        self.ip_address_guacamole_container = Output.from_input(
            str(ip_network_guacamole_containers.available()[0])
        )
        self.ip_address_guacamole_postgresql = Output.from_input(
            str(ip_network_guacamole_postgresql.available()[0])
        )
        self.ip_addresses_srd = Output.from_input(
            [str(ip) for ip in ip_network_secure_research_desktop.available()]
        )
        self.resource_group_name = Output.from_input(props.resource_group_name)
        self.vnet = vnet
