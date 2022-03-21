# Standard library imports
import ipaddress
from typing import Optional, Sequence

# Third party imports
from pulumi import ComponentResource, Input, ResourceOptions, Output
from pulumi_azure_native import network


class NetworkProps:
    """Properties for NetworkComponent"""

    def __init__(
        self,
        resource_group_name: Input[str],
        address_range_vnet: Optional[Input[Sequence[str]]] = [
            "10.0.0.0",
            "10.0.255.255",
        ],
        address_range_application_gateway: Optional[Input[Sequence[str]]] = [
            "10.0.0.0",
            "10.0.0.255",
        ],
        address_range_authelia: Optional[Input[Sequence[str]]] = [
            "10.0.1.0",
            "10.0.1.127",
        ],
        address_range_openldap: Optional[Input[Sequence[str]]] = [
            "10.0.1.128",
            "10.0.1.255",
        ],
        address_range_guacamole_db: Optional[Input[Sequence[str]]] = [
            "10.0.2.0",
            "10.0.2.127",
        ],
        address_range_guacamole_containers: Optional[Input[Sequence[str]]] = [
            "10.0.2.128",
            "10.0.2.255",
        ],
    ):
        self.address_range_vnet = address_range_vnet
        self.address_range_application_gateway = address_range_application_gateway
        self.address_range_authelia = address_range_authelia
        self.address_range_openldap = address_range_openldap
        self.address_range_guacamole_db = address_range_guacamole_db
        self.address_range_guacamole_containers = address_range_guacamole_containers
        self.resource_group_name = resource_group_name

    @staticmethod
    def get_ip_range(ip_address_first, ip_address_last):
        networks = list(
            ipaddress.summarize_address_range(
                ipaddress.ip_address(ip_address_first),
                ipaddress.ip_address(ip_address_last),
            )
        )
        if len(networks) != 1:
            raise ValueError(f"Found {len(networks)} networks when expecting one.")
        return networks[0]


class NetworkComponent(ComponentResource):
    """Deploy networking with Pulumi"""

    def __init__(self, name: str, props: NetworkProps, opts: ResourceOptions = None):
        super().__init__("dsh:network:NetworkComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Set address prefixes from ranges
        ip_network_vnet = props.get_ip_range(*props.address_range_vnet)
        ip_network_application_gateway = props.get_ip_range(*props.address_range_application_gateway)
        ip_network_authelia = props.get_ip_range(*props.address_range_authelia)
        ip_network_openldap = props.get_ip_range(*props.address_range_openldap)
        ip_network_guacamole_db = props.get_ip_range(*props.address_range_guacamole_db)
        ip_network_guacamole_containers = props.get_ip_range(*props.address_range_guacamole_containers)
        ip4 = {
            "openldap": ip_network_openldap[4],
            "guacamole_container": ip_network_guacamole_containers[4],
            "guacamole_postgresql": ip_network_guacamole_db[4],
        }

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
                    address_prefix=str(ip_network_guacamole_db),
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
            ],
            virtual_network_name=f"vnet-{self._name}",
            opts=child_opts,
        )

        # Register outputs
        self.ip4_openldap = Output.from_input(str(ip4["openldap"]))
        self.ip4_guacamole_container = Output.from_input(str(ip4["guacamole_container"]))
        self.ip4_guacamole_postgresql = Output.from_input(str(ip4["guacamole_postgresql"]))
        self.resource_group_name = Output.from_input(props.resource_group_name)
        self.vnet_name = vnet.name
