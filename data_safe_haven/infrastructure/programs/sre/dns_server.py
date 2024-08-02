"""Pulumi component for SRE DNS server"""

from collections.abc import Mapping

import pulumi_random
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, network

from data_safe_haven.functions import b64encode, replace_separators
from data_safe_haven.infrastructure.common import (
    DockerHubCredentials,
    SREDnsIpRanges,
    SREIpRanges,
    get_ip_address_from_container_group,
)
from data_safe_haven.resources import resources_path
from data_safe_haven.types import (
    AzureDnsZoneNames,
    NetworkingPriorities,
    PermittedDomains,
    Ports,
)
from data_safe_haven.utility import FileReader


class SREDnsServerProps:
    """Properties for SREDnsServerComponent"""

    def __init__(
        self,
        dockerhub_credentials: DockerHubCredentials,
        location: Input[str],
        resource_group_name: Input[str],
        shm_fqdn: Input[str],
    ) -> None:
        self.admin_username = "dshadmin"
        self.dockerhub_credentials = dockerhub_credentials
        self.location = location
        self.resource_group_name = resource_group_name
        self.shm_fqdn = shm_fqdn


class SREDnsServerComponent(ComponentResource):
    """Deploy DNS server with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREDnsServerProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:DnsServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "DNS server"} | (tags if tags else {})

        # Generate admin password
        password_admin = pulumi_random.RandomPassword(
            f"{self._name}_password_admin", length=20, special=True, opts=child_opts
        )

        # Read AdGuardHome setup files
        adguard_entrypoint_sh_reader = FileReader(
            resources_path / "dns_server" / "entrypoint.sh"
        )
        adguard_adguardhome_yaml_reader = FileReader(
            resources_path / "dns_server" / "AdGuardHome.mustache.yaml"
        )

        # Expand AdGuardHome YAML configuration
        adguard_adguardhome_yaml_contents = Output.all(
            admin_username=props.admin_username,
            # Only the first 72 bytes of the generated random string will be used but a
            # 20 character UTF-8 string (alphanumeric + special) will not exceed that.
            admin_password_encrypted=password_admin.bcrypt_hash,
            # Use Azure virtual DNS server as upstream
            # https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
            # This server is aware of private DNS zones
            upstream_dns="168.63.129.16",
            filter_allow=Output.from_input(props.shm_fqdn).apply(
                lambda fqdn: [
                    f"*.{fqdn}",
                    *PermittedDomains.ALL,
                ]
            ),
        ).apply(
            lambda mustache_values: adguard_adguardhome_yaml_reader.file_contents(
                mustache_values
            )
        )

        # Define network security group
        nsg = network.NetworkSecurityGroup(
            f"{self._name}_nsg_dns",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-dns",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from attached.",
                    destination_address_prefix=SREDnsIpRanges.vnet.prefix,
                    destination_port_ranges=[Ports.DNS],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowSREInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_ANY,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.vnet.prefix,
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
                    destination_port_ranges=[Ports.DNS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDnsInternetOutbound",
                    priority=NetworkingPriorities.EXTERNAL_INTERNET,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREDnsIpRanges.vnet.prefix,
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

        # Deploy dedicated virtual network
        subnet_name = "DnsSubnet"
        virtual_network = network.VirtualNetwork(
            f"{self._name}_virtual_network",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[SREDnsIpRanges.vnet.prefix],
            ),
            location=props.location,
            resource_group_name=props.resource_group_name,
            subnets=[  # Note that we define subnets inline to avoid creation order issues
                # DNS subnet
                network.SubnetArgs(
                    address_prefix=SREDnsIpRanges.vnet.prefix,
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
            tags=child_tags,
        )

        subnet_dns = network.get_subnet_output(
            subnet_name=subnet_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=virtual_network.name,
        )

        # Define the DNS container group with AdGuard
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-group-dns",
            containers=[
                containerinstance.ContainerArgs(
                    image="adguard/adguardhome:v0.107.52",
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
            # Required due to DockerHub rate-limit: https://docs.docker.com/docker-hub/download-rate-limit/
            image_registry_credentials=[
                {
                    "password": Output.secret(props.dockerhub_credentials.access_token),
                    "server": props.dockerhub_credentials.server,
                    "username": props.dockerhub_credentials.username,
                }
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
            location=props.location,
            os_type=containerinstance.OperatingSystemTypes.LINUX,
            resource_group_name=props.resource_group_name,
            restart_policy=containerinstance.ContainerGroupRestartPolicy.ALWAYS,
            sku=containerinstance.ContainerGroupSku.STANDARD,
            subnet_ids=[containerinstance.ContainerGroupSubnetIdArgs(id=subnet_dns.id)],
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
            tags=child_tags,
        )

        # Create a private DNS zone for each Azure DNS zone name
        self.private_zones = {
            dns_zone_name: network.PrivateZone(
                replace_separators(f"{self._name}_private_zone_{dns_zone_name}", "_"),
                location="Global",
                private_zone_name=f"privatelink.{dns_zone_name}",
                resource_group_name=props.resource_group_name,
                opts=child_opts,
                tags=child_tags,
            )
            for dns_zone_name in AzureDnsZoneNames.ALL
        }

        # Link Azure private DNS zones to virtual network
        for dns_zone_name, private_dns_zone in self.private_zones.items():
            network.VirtualNetworkLink(
                replace_separators(
                    f"{self._name}_private_zone_{dns_zone_name}_vnet_dns_link", "_"
                ),
                location="Global",
                private_zone_name=private_dns_zone.name,
                registration_enabled=False,
                resource_group_name=props.resource_group_name,
                virtual_network=network.SubResourceArgs(id=virtual_network.id),
                virtual_network_link_name=Output.concat(
                    "link-to-", virtual_network.name
                ),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=virtual_network)
                ),
                tags=child_tags,
            )

        # Register outputs
        self.ip_address = get_ip_address_from_container_group(container_group)
        self.password_admin = password_admin
        self.virtual_network = virtual_network
