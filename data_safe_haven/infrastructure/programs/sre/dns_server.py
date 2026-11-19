"""Pulumi component for SRE DNS server"""

from collections.abc import Mapping

import pulumi_random
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, privatedns

from data_safe_haven.functions import replace_separators
from data_safe_haven.infrastructure.common import (
    DockerHubCredentials,
    SREDnsIpRanges,
    SREIpRanges,
)
from data_safe_haven.resources import resources_path
from data_safe_haven.types import (
    AzureDnsZoneNames,
    NetworkingPriorities,
    PermittedDomains,
    Ports,
)
from data_safe_haven.utility import FileReader

from .dns_server_vm import (
    SREDnsServerVMComponent,
    SREDnsServerVMProps,
)


class SREDnsServerProps:
    """Properties for SREDnsServerComponent"""

    def __init__(
        self,
        *,
        allow_workspace_internet: bool,
        data_collection_endpoint_id: Input[str] | None,
        data_collection_rule_id: Input[str] | None,
        dockerhub_credentials: DockerHubCredentials,
        location: str,
        maintenance_configuration_id: Input[str],
        resource_group_name: Input[str],
        shm_fqdn: Input[str],
        timezone: Input[str],
    ) -> None:
        self.admin_username = "dshadmin"
        self.allow_workspace_internet = allow_workspace_internet
        self.data_collection_endpoint_id = data_collection_endpoint_id
        self.data_collection_rule_id = data_collection_rule_id
        self.dockerhub_credentials = dockerhub_credentials
        self.location = location
        self.maintenance_configuration_id = maintenance_configuration_id
        self.resource_group_name = resource_group_name
        self.shm_fqdn = shm_fqdn
        self.timezone = timezone


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

        # Construct permitted and blocked domains
        if not props.allow_workspace_internet:
            filter_allow = Output.from_input(props.shm_fqdn).apply(
                lambda fqdn: [
                    f"*.{fqdn}",
                    *PermittedDomains.all(mapping={"location": props.location}),
                ]
            )
            filter_block = ["*.*"]
        else:
            filter_allow = None
            filter_block = ["example.local"]

        # Expand AdGuardHome YAML configuration
        adguard_adguardhome_yaml_contents = Output.all(
            admin_username=props.admin_username,
            # Only the first 72 bytes of the generated random string will be used but a
            # 20 character UTF-8 string (alphanumeric + special) will not exceed that.
            admin_password_encrypted=password_admin.bcrypt_hash,
            filter_allow=filter_allow,
            filter_block=filter_block,
            # Use Azure virtual DNS server as upstream
            # https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
            # This server is aware of private DNS zones
            upstream_dns="168.63.129.16",
        ).apply(adguard_adguardhome_yaml_reader.file_contents)

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
                    description="Allow inbound connections from monitoring tools.",
                    destination_address_prefix=SREDnsIpRanges.vnet.prefix,
                    destination_port_ranges=[Ports.AZURE_MONITORING],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowMonitoringToolsInbound",
                    priority=NetworkingPriorities.AZURE_MONITORING_SOURCES,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.monitoring.prefix,
                    source_port_range="*",
                ),
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
                    priority=NetworkingPriorities.EXTERNAL_INTERNET_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREDnsIpRanges.vnet.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to monitoring tools.",
                    destination_address_prefix=SREIpRanges.monitoring.prefix,
                    destination_port_ranges=[Ports.HTTPS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowMonitoringToolsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_MONITORING_TOOLS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREDnsIpRanges.vnet.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to external repositories over the internet.",
                    destination_address_prefix="Internet",
                    destination_port_ranges=[Ports.HTTP, Ports.HTTPS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowPackagesInternetOutbound",
                    priority=NetworkingPriorities.EXTERNAL_INTERNET,
                    protocol=network.SecurityRuleProtocol.TCP,
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
                    ignore_changes=["virtual_network_peerings"],
                    delete_before_replace=True,
                    replace_on_changes=["subnets[*].delegations"],
                ),  # allow peering to SRE virtual network
            ),
            tags=child_tags,
        )

        subnet_dns = network.get_subnet_output(
            subnet_name=subnet_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=virtual_network.name,
        )

        dns_server_vm_component = SREDnsServerVMComponent(
            "dns_server_vm",
            stack_name,
            SREDnsServerVMProps(
                adguardhome_yaml_content=adguard_adguardhome_yaml_contents,
                admin_password=password_admin.result,
                data_collection_rule_id=props.data_collection_rule_id,
                data_collection_endpoint_id=props.data_collection_endpoint_id,
                dockerhub_credentials=props.dockerhub_credentials,
                entrypoint_sh_content=adguard_entrypoint_sh_reader.file_contents(),
                location=props.location,
                maintenance_configuration_id=props.maintenance_configuration_id,
                resource_group_name=props.resource_group_name,
                subnet_dns=subnet_dns,
                virtual_network=virtual_network,
                vm_size="Standard_B2als_v2",
            ),
            tags=child_tags,
        )

        # Create a private DNS zone for each Azure DNS zone name
        self.private_zones = {
            dns_zone_name: privatedns.PrivateZone(
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
            privatedns.VirtualNetworkLink(
                resource_name=replace_separators(
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
        self.ip_address = dns_server_vm_component.exports["ip_address"]
        self.password_admin = password_admin
        self.virtual_network = virtual_network

        self.register_outputs({})
