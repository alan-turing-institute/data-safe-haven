"""Pulumi component for SHM networking"""

from collections.abc import Mapping, Sequence

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

from data_safe_haven.external import AzureIPv4Range
from data_safe_haven.infrastructure.common import azure_dns_zone_names


class SHMNetworkingProps:
    """Properties for SHMNetworkingComponent"""

    def __init__(
        self,
        admin_ip_addresses: Input[Sequence[str]],
        fqdn: Input[str],
        location: Input[str],
        record_domain_verification: Input[str],
    ) -> None:
        # Virtual network and subnet IP ranges
        self.vnet_iprange = AzureIPv4Range("10.0.0.0", "10.0.255.255")
        # Firewall subnet must be at least /26 in size (64 addresses)
        self.subnet_firewall_iprange = self.vnet_iprange.next_subnet(64)
        # Monitoring subnet needs 2 IP addresses for automation and 13 for log analytics
        self.subnet_monitoring_iprange = self.vnet_iprange.next_subnet(32)
        # Other variables
        self.admin_ip_addresses = admin_ip_addresses
        self.fqdn = fqdn
        self.location = location
        self.record_domain_verification = record_domain_verification


class SHMNetworkingComponent(ComponentResource):
    """Deploy SHM networking with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SHMNetworkingProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:shm:NetworkingComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-networking",
            opts=child_opts,
            tags=child_tags,
        )

        # Define NSGs
        nsg_monitoring = network.NetworkSecurityGroup(
            f"{self._name}_nsg_monitoring",
            network_security_group_name=f"{stack_name}-nsg-monitoring",
            resource_group_name=resource_group.name,
            security_rules=[],
            opts=child_opts,
            tags=child_tags,
        )

        # Define route table
        route_table = network.RouteTable(
            f"{self._name}_route_table",
            location=props.location,
            resource_group_name=resource_group.name,
            route_table_name=f"{stack_name}-route",
            routes=[],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=["routes"]
                ),  # allow routes to be created outside this definition
            ),
            tags=child_tags,
        )

        # Define the virtual network and its subnets
        subnet_firewall_name = "AzureFirewallSubnet"  # this name is forced by https://docs.microsoft.com/en-us/azure/firewall/tutorial-firewall-deploy-portal
        subnet_monitoring_name = "MonitoringSubnet"
        virtual_network = network.VirtualNetwork(
            f"{self._name}_virtual_network",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[str(props.vnet_iprange)],
            ),
            resource_group_name=resource_group.name,
            subnets=[  # Note that we define subnets inline to avoid creation order issues
                # AzureFirewall subnet
                network.SubnetArgs(
                    address_prefix=str(props.subnet_firewall_iprange),
                    name=subnet_firewall_name,
                    network_security_group=None,  # the firewall subnet must NOT have an NSG
                    route_table=None,  # the firewall subnet must NOT be attached to the route table
                ),
                # Monitoring subnet
                network.SubnetArgs(
                    address_prefix=str(props.subnet_monitoring_iprange),
                    name=subnet_monitoring_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_monitoring.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
            ],
            virtual_network_name=f"{stack_name}-vnet",
            virtual_network_peerings=[],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=[
                        "subnets",
                        "virtual_network_peerings",
                    ]
                ),  # allow SRE virtual networks to peer to this
            ),
            tags=child_tags,
        )

        # Define SHM DNS zone
        dns_zone = network.Zone(
            f"{self._name}_dns_zone",
            location="Global",
            resource_group_name=resource_group.name,
            zone_name=props.fqdn,
            zone_type=network.ZoneType.PUBLIC,
            opts=child_opts,
            tags=child_tags,
        )
        network.RecordSet(
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
            zone_name=dns_zone.name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=dns_zone)),
        )
        network.RecordSet(
            f"{self._name}_domain_verification_record",
            record_type="TXT",
            relative_record_set_name="@",
            resource_group_name=resource_group.name,
            ttl=3600,
            txt_records=[
                network.TxtRecordArgs(value=[props.record_domain_verification])
            ],
            zone_name=dns_zone.name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=dns_zone)),
        )

        # Set up private link domains
        private_zone_ids: list[Output[str]] = []
        for dns_zone_name in azure_dns_zone_names():
            private_zone = network.PrivateZone(
                f"{self._name}_private_zone_{dns_zone_name}",
                location="Global",
                private_zone_name=f"privatelink.{dns_zone_name}",
                resource_group_name=resource_group.name,
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=dns_zone)
                ),
                tags=child_tags,
            )
            network.VirtualNetworkLink(
                f"{self._name}_private_zone_{dns_zone_name}_vnet_link",
                location="Global",
                private_zone_name=private_zone.name,
                registration_enabled=False,
                resource_group_name=resource_group.name,
                virtual_network=network.SubResourceArgs(id=virtual_network.id),
                virtual_network_link_name=Output.concat(
                    "link-to-", virtual_network.name
                ),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=private_zone)
                ),
                tags=child_tags,
            )
            private_zone_ids.append(
                private_zone.id.apply(
                    lambda zone_id: "".join(zone_id.partition("privatelink.")[:-1])
                )
            )

        # Register outputs
        self.dns_zone = dns_zone
        self.private_dns_zone_base_id = private_zone_ids[0]
        self.resource_group_name = Output.from_input(resource_group.name)
        self.route_table = route_table
        self.subnet_firewall = network.get_subnet_output(
            subnet_name=subnet_firewall_name,
            resource_group_name=resource_group.name,
            virtual_network_name=virtual_network.name,
        )
        self.subnet_monitoring = network.get_subnet_output(
            subnet_name=subnet_monitoring_name,
            resource_group_name=resource_group.name,
            virtual_network_name=virtual_network.name,
        )
        self.virtual_network = virtual_network

        # Register exports
        self.exports = {
            "fqdn_nameservers": self.dns_zone.name_servers,
            "private_dns_zone_base_id": self.private_dns_zone_base_id,
            "resource_group_name": resource_group.name,
            "subnet_monitoring_prefix": self.subnet_monitoring.apply(
                lambda s: str(s.address_prefix) if s.address_prefix else ""
            ),
            "virtual_network_name": virtual_network.name,
        }
