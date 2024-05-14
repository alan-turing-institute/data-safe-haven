"""Pulumi component for SHM traffic routing"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network

from data_safe_haven.infrastructure.common import (
    SREIpRanges,
    get_id_from_subnet,
)
from data_safe_haven.types import (
    FirewallPriorities,
    PermittedDomains,
    Ports,
)


class SHMFirewallProps:
    """Properties for SHMFirewallComponent"""

    def __init__(
        self,
        dns_zone: Input[network.Zone],
        location: Input[str],
        resource_group_name: Input[str],
        route_table_name: Input[str],
        subnet_firewall: Input[network.GetSubnetResult],
    ) -> None:
        self.dns_zone_name = Output.from_input(dns_zone).apply(lambda zone: zone.name)
        self.location = location
        self.resource_group_name = resource_group_name
        self.route_table_name = route_table_name
        self.subnet_firewall_id = Output.from_input(subnet_firewall).apply(
            get_id_from_subnet
        )


class SHMFirewallComponent(ComponentResource):
    """Deploy SHM routing with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SHMFirewallProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:shm:FirewallComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Important IP addresses
        # https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
        external_dns_resolver = "168.63.129.16"
        ntp_ip_addresses = [
            "216.239.35.0",
            "216.239.35.4",
            "216.239.35.8",
            "216.239.35.12",
        ]
        sre_identity_server_subnets = [
            str(SREIpRanges(idx).identity_containers)
            for idx in range(1, SREIpRanges.max_index)
        ]
        sre_package_repositories_subnets = [
            str(SREIpRanges(idx).user_services_software_repositories)
            for idx in range(1, SREIpRanges.max_index)
        ]
        sre_remote_desktop_gateway_subnets = [
            str(SREIpRanges(idx).guacamole_containers)
            for idx in range(1, SREIpRanges.max_index)
        ]
        sre_apt_proxy_servers = [
            str(SREIpRanges(idx).apt_proxy_server)
            for idx in range(1, SREIpRanges.max_index)
        ]
        sre_workspaces_subnets = [
            str(SREIpRanges(idx).workspaces) for idx in range(1, SREIpRanges.max_index)
        ]

        # Deploy IP address
        public_ip = network.PublicIPAddress(
            f"{self._name}_pip_firewall",
            public_ip_address_name=f"{stack_name}-pip-firewall",
            public_ip_allocation_method=network.IPAllocationMethod.STATIC,
            resource_group_name=props.resource_group_name,
            sku=network.PublicIPAddressSkuArgs(
                name=network.PublicIPAddressSkuName.STANDARD
            ),
            opts=child_opts,
            tags=child_tags,
        )

        # Deploy firewall
        firewall = network.AzureFirewall(
            f"{self._name}_firewall",
            additional_properties={"Network.DNS.EnableProxy": "true"},
            application_rule_collections=[
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(type="Allow"),
                    name=f"{stack_name}-any",
                    priority=FirewallPriorities.ALL,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external Azure Automation requests",
                            name="AllowExternalAzureAutomationOperations",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.HTTPS),
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=["*"],
                            target_fqdns=[
                                "GuestAndHybridManagement",
                            ],
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external NTP requests",
                            name="AllowExternalGoogleNTP",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.NTP),
                                    protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTP,
                                )
                            ],
                            source_addresses=["*"],
                            target_fqdns=PermittedDomains.TIME_SERVERS,
                        ),
                    ],
                ),
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(type="Allow"),
                    name=f"{stack_name}-sre-identity-servers",
                    priority=FirewallPriorities.SRE_IDENTITY_CONTAINERS,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external OAuth login requests",
                            name="AllowExternalOAuthLogin",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.HTTPS),
                                    protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                                )
                            ],
                            source_addresses=sre_identity_server_subnets,
                            target_fqdns=PermittedDomains.MICROSOFT_IDENTITY,
                        ),
                    ],
                ),
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(type="Allow"),
                    name=f"{stack_name}-sre-package-repositories",
                    priority=FirewallPriorities.SRE_USER_SERVICES_SOFTWARE_REPOSITORIES,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external CRAN package requests",
                            name="AllowExternalPackageDownloadCRAN",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.HTTPS),
                                    protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                                )
                            ],
                            source_addresses=sre_package_repositories_subnets,
                            target_fqdns=PermittedDomains.SOFTWARE_REPOSITORIES_R,
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external PyPI package requests",
                            name="AllowExternalPackageDownloadPyPI",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.HTTPS),
                                    protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                                )
                            ],
                            source_addresses=sre_package_repositories_subnets,
                            target_fqdns=PermittedDomains.SOFTWARE_REPOSITORIES_PYTHON,
                        ),
                    ],
                ),
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(type="Allow"),
                    name=f"{stack_name}-sre-remote-desktop-gateways",
                    priority=FirewallPriorities.SRE_GUACAMOLE_CONTAINERS,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external OAuth login requests",
                            name="AllowExternalOAuthLogin",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.HTTPS),
                                    protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                                )
                            ],
                            source_addresses=sre_remote_desktop_gateway_subnets,
                            target_fqdns=PermittedDomains.MICROSOFT_LOGIN,
                        ),
                    ],
                ),
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(type="Allow"),
                    name=f"{stack_name}-sre-apt-proxy-servers",
                    priority=FirewallPriorities.SRE_APT_PROXY_SERVER,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external apt repository requests",
                            name="AllowExternalAptRepositories",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.HTTP),
                                    protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTP,
                                ),
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.HTTPS),
                                    protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                                ),
                            ],
                            source_addresses=sre_apt_proxy_servers,
                            target_fqdns=PermittedDomains.APT_REPOSITORIES,
                        ),
                    ],
                ),
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(type="Allow"),
                    name=f"{stack_name}-sre-workspaces",
                    priority=FirewallPriorities.SRE_WORKSPACES,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external Linux ClamAV update requests",
                            name="AllowExternalLinuxClamAVUpdate",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.HTTP),
                                    protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTP,
                                ),
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.HTTPS),
                                    protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                                ),
                            ],
                            source_addresses=sre_workspaces_subnets,
                            target_fqdns=PermittedDomains.CLAMAV_UPDATES,
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external Linux ClamAV update requests",
                            name="AllowExternalUbuntuKeyserver",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.CLAMAV),
                                    protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTP,
                                ),
                            ],
                            source_addresses=sre_workspaces_subnets,
                            target_fqdns=PermittedDomains.UBUNTU_KEYSERVER,
                        ),
                    ],
                ),
            ],
            azure_firewall_name=f"{stack_name}-firewall",
            ip_configurations=[
                network.AzureFirewallIPConfigurationArgs(
                    name="FirewallIpConfiguration",
                    public_ip_address=network.SubResourceArgs(id=public_ip.id),
                    subnet=network.SubResourceArgs(id=props.subnet_firewall_id),
                )
            ],
            location=props.location,
            network_rule_collections=[
                network.AzureFirewallNetworkRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(type="Allow"),
                    name=f"{stack_name}-all",
                    priority=FirewallPriorities.ALL,
                    rules=[
                        network.AzureFirewallNetworkRuleArgs(
                            description="Allow external Azure Automation requests",
                            destination_addresses=["GuestAndHybridManagement"],
                            destination_ports=["*"],
                            name="AllowExternalAzureAutomationOperations",
                            protocols=[
                                network.AzureFirewallNetworkRuleProtocol.TCP,
                                network.AzureFirewallNetworkRuleProtocol.UDP,
                            ],
                            source_addresses=["*"],
                        ),
                        network.AzureFirewallNetworkRuleArgs(
                            description="Allow external NTP requests",
                            destination_addresses=ntp_ip_addresses,
                            destination_ports=[Ports.NTP],
                            name="AllowExternalNTP",
                            protocols=[network.AzureFirewallNetworkRuleProtocol.UDP],
                            source_addresses=["*"],
                        ),
                    ],
                ),
            ],
            resource_group_name=props.resource_group_name,
            sku=network.AzureFirewallSkuArgs(
                name=network.AzureFirewallSkuName.AZF_W_V_NET,
                tier=network.AzureFirewallSkuTier.STANDARD,
            ),
            threat_intel_mode="Alert",
            zones=[],
            opts=child_opts,
            tags=child_tags,
        )

        # Route all connected traffic through the firewall
        private_ip_address = firewall.ip_configurations.apply(
            lambda cfgs: (
                ""
                if not cfgs
                else next(filter(lambda _: _, [cfg.private_ip_address for cfg in cfgs]))
            )
        )
        network.Route(
            f"{self._name}_route_via_firewall",
            address_prefix="0.0.0.0/0",
            next_hop_ip_address=private_ip_address,
            next_hop_type=network.RouteNextHopType.VIRTUAL_APPLIANCE,
            resource_group_name=props.resource_group_name,
            route_name="ViaFirewall",
            route_table_name=props.route_table_name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=firewall)),
        )

        # Register outputs
        self.external_dns_resolver = external_dns_resolver
        self.ntp_fqdns = PermittedDomains.TIME_SERVERS
        self.ntp_ip_addresses = ntp_ip_addresses
        self.public_ip_id = public_ip.id

        # Register exports
        self.exports = {
            "private_ip_address": private_ip_address,
        }
