"""Pulumi component for SRE DNS server"""
import pathlib

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, network, resources

from data_safe_haven.functions import (
    allowed_dns_lookups,
    b64encode,
    bcrypt_encode,
    ordered_private_dns_zones,
)
from data_safe_haven.infrastructure.common import (
    NetworkingPriorities,
    SREDnsIpRanges,
    SREIpRanges,
    get_ip_address_from_container_group,
)
from data_safe_haven.utility import FileReader


class SREDnsServerProps:
    """Properties for SREDnsServerComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        admin_password_salt: Input[str],
        location: Input[str],
        shm_fqdn: Input[str],
        shm_networking_resource_group_name: Input[str],
        sre_index: Input[int],
    ) -> None:
        subnet_ranges = Output.from_input(sre_index).apply(lambda idx: SREIpRanges(idx))
        self.admin_password = Output.secret(admin_password)
        self.admin_password_salt = Output.secret(admin_password_salt)
        self.admin_username = ("dshadmin",)
        self.ip_range_prefix = str(SREDnsIpRanges().vnet)
        self.location = location
        self.shm_fqdn = shm_fqdn
        self.shm_networking_resource_group_name = shm_networking_resource_group_name
        self.sre_vnet_prefix = subnet_ranges.apply(lambda r: str(r.vnet))


class SREDnsServerComponent(ComponentResource):
    """Deploy DNS server with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREDnsServerProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:DnsServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-dns",
            opts=child_opts,
        )

        # Read AdGuardHome setup files
        resources_path = (
            pathlib.Path(__file__).parent.parent.parent / "resources" / "dns_server"
        )
        adguard_entrypoint_sh_reader = FileReader(resources_path / "entrypoint.sh")
        adguard_adguardhome_yaml_reader = FileReader(
            resources_path / "AdGuardHome.mustache.yaml"
        )

        # Expand AdGuardHome YAML configuration
        adguard_adguardhome_yaml_contents = Output.all(
            admin_username=props.admin_username,
            admin_password_encrypted=Output.all(
                password=props.admin_password, salt=props.admin_password_salt
            ).apply(lambda kwargs: bcrypt_encode(kwargs["password"], kwargs["salt"])),
            # Use Azure virtual DNS server as upstream
            # https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
            # This server is aware of private DNS zones
            upstream_dns="168.63.129.16",
            filter_allow=Output.from_input(props.shm_fqdn).apply(
                lambda fqdn: [f"*.{fqdn}", *allowed_dns_lookups()]
            ),
        ).apply(
            lambda mustache_values: adguard_adguardhome_yaml_reader.file_contents(
                mustache_values
            )
        )

        # Define network security group
        nsg = network.NetworkSecurityGroup(
            f"{self._name}_nsg_dns",
            network_security_group_name=f"{stack_name}-nsg-dns",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from attached.",
                    destination_address_prefix=props.ip_range_prefix,
                    destination_port_ranges=["53"],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowSREInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_ANY,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=props.sre_vnet_prefix,
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
                    description="Allow outbound DNS traffic over the internet.",
                    destination_address_prefix="Internet",
                    destination_port_ranges=["53"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDnsInternetOutbound",
                    priority=NetworkingPriorities.EXTERNAL_INTERNET,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=props.ip_range_prefix,
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
        )

        # Deploy dedicated virtual network
        subnet_name = "DnsSubnet"
        virtual_network = network.VirtualNetwork(
            f"{self._name}_virtual_network",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[props.ip_range_prefix],
            ),
            resource_group_name=resource_group.name,
            subnets=[  # Note that we define subnets inline to avoid creation order issues
                # DNS subnet
                network.SubnetArgs(
                    address_prefix=props.ip_range_prefix,
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name=subnet_name,
                    network_security_group=network.NetworkSecurityGroupArgs(id=nsg.id),
                    route_table=None,
                ),
            ],
            virtual_network_name=f"{stack_name}-vnet-dns",
            virtual_network_peerings=[],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=["virtual_network_peerings"]
                ),  # allow peering to SRE virtual network
            ),
        )

        subnet_dns = network.get_subnet_output(
            subnet_name=subnet_name,
            resource_group_name=resource_group.name,
            virtual_network_name=virtual_network.name,
        )

        # Define a network profile
        container_network_profile = network.NetworkProfile(
            f"{self._name}_container_network_profile",
            container_network_interface_configurations=[
                network.ContainerNetworkInterfaceConfigurationArgs(
                    ip_configurations=[
                        network.IPConfigurationProfileArgs(
                            name="ipconfigdns",
                            subnet=network.SubnetArgs(id=subnet_dns.id),
                        )
                    ],
                    name="networkinterfaceconfigdns",
                )
            ],
            network_profile_name=f"{stack_name}-np-dns",
            resource_group_name=resource_group.name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    depends_on=[virtual_network],
                    ignore_changes=[
                        "container_network_interface_configurations"
                    ],  # allow container groups to be registered to this interface
                ),
            ),
        )

        # Define the DNS container group with AdGuard
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-group-dns",
            containers=[
                containerinstance.ContainerArgs(
                    image="adguard/adguardhome:v0.107.36",
                    name="adguard",
                    # Providing "command" overwrites the CMD arguments in the Docker
                    # image, so we can either provide them here or set defaults in our
                    # custom entrypoint.
                    #
                    # The entrypoint script will not be executable when mounted so we
                    # need to explicitly run it with /bin/sh
                    command=["/bin/sh", "/opt/adguardhome/custom/entrypoint.sh"],
                    environment_variables=[],
                    # All Azure Container Instances need to expose port 80 on at least
                    # one container. In this case, the web interface is on 3000 so we
                    # are not exposing that to users.
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=53,
                            protocol=containerinstance.ContainerGroupNetworkProtocol.UDP,
                        ),
                        containerinstance.ContainerPortArgs(
                            port=80,
                            protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                        ),
                    ],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=1,
                            memory_in_gb=1,
                        ),
                    ),
                    volume_mounts=[
                        containerinstance.VolumeMountArgs(
                            mount_path="/opt/adguardhome/custom",
                            name="adguard-opt-adguardhome-custom",
                            read_only=True,
                        ),
                    ],
                ),
            ],
            ip_address=containerinstance.IpAddressArgs(
                ports=[
                    containerinstance.PortArgs(
                        port=80,
                        protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                    )
                ],
                type=containerinstance.ContainerGroupIpAddressType.PRIVATE,
            ),
            network_profile=containerinstance.ContainerGroupNetworkProfileArgs(
                id=container_network_profile.id,
            ),
            os_type=containerinstance.OperatingSystemTypes.LINUX,
            resource_group_name=resource_group.name,
            restart_policy=containerinstance.ContainerGroupRestartPolicy.ALWAYS,
            sku=containerinstance.ContainerGroupSku.STANDARD,
            volumes=[
                containerinstance.VolumeArgs(
                    name="adguard-opt-adguardhome-custom",
                    secret={
                        "entrypoint.sh": b64encode(
                            adguard_entrypoint_sh_reader.file_contents()
                        ),
                        "AdGuardHome.yaml": adguard_adguardhome_yaml_contents.apply(
                            lambda s: b64encode(s)
                        ),
                    },
                ),
            ],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    delete_before_replace=True,
                    replace_on_changes=["containers"],
                ),
            ),
        )

        # Link virtual network to SHM private DNS zones
        for private_link_domain in ordered_private_dns_zones():
            network.VirtualNetworkLink(
                f"{self._name}_private_zone_{private_link_domain}_vnet_dns_link",
                location="Global",
                private_zone_name=f"privatelink.{private_link_domain}",
                registration_enabled=False,
                resource_group_name=props.shm_networking_resource_group_name,
                virtual_network=network.SubResourceArgs(id=virtual_network.id),
                virtual_network_link_name=Output.concat(
                    "link-to-", virtual_network.name
                ),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=virtual_network)
                ),
            )

        # Register outputs
        self.ip_address = get_ip_address_from_container_group(container_group)
        self.resource_group = resource_group
        self.virtual_network = virtual_network