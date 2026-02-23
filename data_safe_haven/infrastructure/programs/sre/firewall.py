"""Pulumi component for SRE traffic routing"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import monitor, network

from data_safe_haven.infrastructure.common import (
    get_address_prefixes_from_subnet,
    get_id_from_subnet,
)
from data_safe_haven.infrastructure.components import WrappedLogAnalyticsWorkspace
from data_safe_haven.types import (
    AzureServiceTag,
    FirewallPriorities,
    ForbiddenDomains,
    PermittedDomains,
    Ports,
)


class SREFirewallProps:
    """Properties for SREFirewallComponent"""

    def __init__(
        self,
        *,
        allow_workspace_internet: bool,
        location: Input[str],
        log_analytics_workspace: Input[WrappedLogAnalyticsWorkspace],
        resource_group_name: Input[str],
        route_table_name: Input[str],
        subnet_apt_proxy_server: Input[network.GetSubnetResult],
        subnet_clamav_mirror: Input[network.GetSubnetResult],
        subnet_dns_sidecar: Input[network.GetSubnetResult],
        subnet_firewall: Input[network.GetSubnetResult],
        subnet_firewall_management: Input[network.GetSubnetResult],
        subnet_guacamole_containers: Input[network.GetSubnetResult],
        subnet_identity_containers: Input[network.GetSubnetResult],
        subnet_user_services_gitea_mirror: Input[network.GetSubnetResult] | None,
        subnet_user_services_software_repositories: (
            Input[network.GetSubnetResult] | None
        ),
        subnet_workspaces: Input[network.GetSubnetResult],
    ) -> None:
        self.allow_workspace_internet = allow_workspace_internet
        self.location = location
        self.log_analytics_workspace = log_analytics_workspace
        self.resource_group_name = resource_group_name
        self.route_table_name = route_table_name
        self.subnet_apt_proxy_server_prefixes = Output.from_input(
            subnet_apt_proxy_server
        ).apply(get_address_prefixes_from_subnet)
        self.subnet_clamav_mirror_prefixes = Output.from_input(
            subnet_clamav_mirror
        ).apply(get_address_prefixes_from_subnet)

        self.subnet_dns_sidecar_prefixes = Output.from_input(subnet_dns_sidecar).apply(
            get_address_prefixes_from_subnet
        )

        self.subnet_identity_containers_prefixes = Output.from_input(
            subnet_identity_containers
        ).apply(get_address_prefixes_from_subnet)
        self.subnet_firewall_id = Output.from_input(subnet_firewall).apply(
            get_id_from_subnet
        )
        self.subnet_firewall_management_id = Output.from_input(
            subnet_firewall_management
        ).apply(get_id_from_subnet)
        self.subnet_guacamole_containers_prefixes = Output.from_input(
            subnet_guacamole_containers
        ).apply(get_address_prefixes_from_subnet)

        self.subnet_user_services_software_repositories_prefixes: (
            Output[list[str]] | None
        ) = None

        if subnet_user_services_software_repositories is not None:
            self.subnet_user_services_software_repositories_prefixes = (
                Output.from_input(subnet_user_services_software_repositories).apply(
                    get_address_prefixes_from_subnet
                )
            )

        self.subnet_user_services_gitea_mirror_prefixes: Output[list[str]] | None = None
        if subnet_user_services_gitea_mirror is not None:
            self.subnet_user_services_gitea_mirror_prefixes = Output.from_input(
                subnet_user_services_gitea_mirror
            ).apply(get_address_prefixes_from_subnet)
        self.subnet_workspaces_prefixes = Output.from_input(subnet_workspaces).apply(
            get_address_prefixes_from_subnet
        )


class SREFirewallComponent(ComponentResource):
    """Deploy an SRE firewall with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREFirewallProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:FirewallComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "firewall"} | (tags if tags else {})

        # Deploy IP address
        public_ip = network.PublicIPAddress(
            f"{self._name}_pip_firewall",
            location=props.location,
            public_ip_address_name=f"{stack_name}-pip-firewall",
            public_ip_allocation_method=network.IPAllocationMethod.STATIC,
            resource_group_name=props.resource_group_name,
            sku=network.PublicIPAddressSkuArgs(
                name=network.PublicIPAddressSkuName.STANDARD
            ),
            opts=child_opts,
            tags=child_tags,
        )

        # Note that a Basic SKU firewall needs a separate management IP address and
        # subnet to handle traffic for communicating updates and health metrics to and
        # from Microsoft.
        public_ip_management = network.PublicIPAddress(
            f"{self._name}_pip_firewall_management",
            location=props.location,
            public_ip_address_name=f"{stack_name}-pip-firewall-management",
            public_ip_allocation_method=network.IPAllocationMethod.STATIC,
            resource_group_name=props.resource_group_name,
            sku=network.PublicIPAddressSkuArgs(
                name=network.PublicIPAddressSkuName.STANDARD
            ),
            opts=child_opts,
            tags=child_tags,
        )

        application_rule_collections_common = [
            network.AzureFirewallApplicationRuleCollectionArgs(
                action=network.AzureFirewallRCActionArgs(
                    type=network.AzureFirewallRCActionType.ALLOW
                ),
                name="apt-proxy-server-allow",
                priority=FirewallPriorities.SRE_APT_PROXY_SERVER,
                rules=[
                    network.AzureFirewallApplicationRuleArgs(
                        description="Allow external apt repository requests",
                        name="AllowAptRepositories",
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
                        source_addresses=props.subnet_apt_proxy_server_prefixes,
                        target_fqdns=PermittedDomains.APT_REPOSITORIES,
                    ),
                ],
            ),
            network.AzureFirewallApplicationRuleCollectionArgs(
                action=network.AzureFirewallRCActionArgs(
                    type=network.AzureFirewallRCActionType.ALLOW
                ),
                name="clamav-mirror-allow",
                priority=FirewallPriorities.SRE_CLAMAV_MIRROR,
                rules=[
                    network.AzureFirewallApplicationRuleArgs(
                        description="Allow external ClamAV definition update requests",
                        name="AllowClamAVDefinitionUpdates",
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
                        source_addresses=props.subnet_clamav_mirror_prefixes,
                        target_fqdns=PermittedDomains.CLAMAV_UPDATES,
                    ),
                ],
            ),
            network.AzureFirewallApplicationRuleCollectionArgs(
                action=network.AzureFirewallRCActionArgs(
                    type=network.AzureFirewallRCActionType.ALLOW
                ),
                name="identity-server-allow",
                priority=FirewallPriorities.SRE_IDENTITY_CONTAINERS,
                rules=[
                    network.AzureFirewallApplicationRuleArgs(
                        description="Allow Microsoft OAuth login requests",
                        name="AllowMicrosoftOAuthLogin",
                        protocols=[
                            network.AzureFirewallApplicationRuleProtocolArgs(
                                port=int(Ports.HTTPS),
                                protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                            )
                        ],
                        source_addresses=props.subnet_identity_containers_prefixes,
                        target_fqdns=PermittedDomains.MICROSOFT_IDENTITY,
                    ),
                ],
            ),
            network.AzureFirewallApplicationRuleCollectionArgs(
                action=network.AzureFirewallRCActionArgs(
                    type=network.AzureFirewallRCActionType.ALLOW
                ),
                name="remote-desktop-gateway-allow",
                priority=FirewallPriorities.SRE_GUACAMOLE_CONTAINERS,
                rules=[
                    network.AzureFirewallApplicationRuleArgs(
                        description="Allow Microsoft OAuth login requests",
                        name="AllowMicrosoftOAuthLogin",
                        protocols=[
                            network.AzureFirewallApplicationRuleProtocolArgs(
                                port=int(Ports.HTTPS),
                                protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                            )
                        ],
                        source_addresses=props.subnet_guacamole_containers_prefixes,
                        target_fqdns=PermittedDomains.MICROSOFT_LOGIN,
                    ),
                ],
            ),
            network.AzureFirewallApplicationRuleCollectionArgs(
                action=network.AzureFirewallRCActionArgs(
                    type=network.AzureFirewallRCActionType.ALLOW
                ),
                name="dns-sidecar-allow",
                priority=FirewallPriorities.SRE_DNS_SIDECAR,
                rules=[
                    network.AzureFirewallApplicationRuleArgs(
                        description="Allow Microsoft Container Registry downloads.",
                        name="AllowMicrosoftContainerRegistryDownload",
                        protocols=[
                            network.AzureFirewallApplicationRuleProtocolArgs(
                                port=int(Ports.HTTPS),
                                protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                            )
                        ],
                        source_addresses=props.subnet_dns_sidecar_prefixes,
                        target_fqdns=PermittedDomains.MICROSOFT_CONTAINER_REGISTRY,
                    ),
                    network.AzureFirewallApplicationRuleArgs(
                        description="Allow using Managed Identities.",
                        name="AllowUsingManagedIdentities",
                        protocols=[
                            network.AzureFirewallApplicationRuleProtocolArgs(
                                port=int(Ports.HTTPS),
                                protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                            )
                        ],
                        source_addresses=props.subnet_dns_sidecar_prefixes,
                        target_fqdns=PermittedDomains.AZURE_MANAGED_IDENTITIES,
                    ),
                ],
            ),
        ]

        # Enabling DNS Monitors to connect to Azure AD and ARM.
        # IMPORTANT: The subnets in this list will have access to the Azure Services with tags
        # AzureResourceManager and AzureActiveDirectory. If adding user-facing subnets, make sure
        # it's not possible to egress data via these services.

        network_rule_collections = [
            network.AzureFirewallNetworkRuleCollectionArgs(
                action=network.AzureFirewallRCActionArgs(
                    type=network.AzureFirewallRCActionType.ALLOW
                ),
                name="dns-sidecar-allow",
                priority=FirewallPriorities.ALL,
                rules=[
                    network.AzureFirewallNetworkRuleArgs(
                        description="Enables access to the Azure Resource Manager from the DNS Sidecar.",
                        destination_addresses=[AzureServiceTag.AZURE_RESOURCE_MANAGER],
                        destination_ports=[Ports.HTTPS],
                        name="allow-azure-resource-manager",
                        protocols=[network.AzureFirewallNetworkRuleProtocol.TCP],
                        source_addresses=props.subnet_dns_sidecar_prefixes,
                    ),
                    network.AzureFirewallNetworkRuleArgs(
                        description="Enables access to the Azure Active Directory from the DNS Sidecar.",
                        destination_addresses=[AzureServiceTag.AZURE_ACTIVE_DIRECTORY],
                        destination_ports=[Ports.HTTPS],
                        name="allow-azure-active-directory",
                        protocols=[network.AzureFirewallNetworkRuleProtocol.TCP],
                        source_addresses=props.subnet_dns_sidecar_prefixes,
                    ),
                ],
            ),
        ]

        if props.allow_workspace_internet:
            application_rule_collections = application_rule_collections_common
            # A network rule is used as application rules are restricted to certain
            # types of traffic, e.g. HTTP, HTTPS
            network_rule_collections += [
                network.AzureFirewallNetworkRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(
                        type=network.AzureFirewallRCActionType.ALLOW
                    ),
                    name="workspaces-allow-all",
                    priority=FirewallPriorities.SRE_WORKSPACES,
                    rules=[
                        network.AzureFirewallNetworkRuleArgs(
                            description="Enables internet access to workspaces.",
                            destination_addresses=["*"],
                            destination_ports=["*"],
                            name="allow-internet-access",
                            protocols=[network.AzureFirewallNetworkRuleProtocol.ANY],
                            source_addresses=props.subnet_workspaces_prefixes,
                        )
                    ],
                ),
            ]
        else:
            application_rule_collections = [
                *application_rule_collections_common,
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(
                        type=network.AzureFirewallRCActionType.ALLOW
                    ),
                    name="workspaces-allow-restricted",
                    priority=FirewallPriorities.SRE_WORKSPACES,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external Ubuntu keyserver requests",
                            name="AllowUbuntuKeyserver",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.HKP),
                                    protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTP,
                                ),
                            ],
                            source_addresses=props.subnet_workspaces_prefixes,
                            target_fqdns=PermittedDomains.UBUNTU_KEYSERVER,
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external Ubuntu Snap Store access",
                            name="AllowUbuntuSnapcraft",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.HTTPS),
                                    protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                                ),
                            ],
                            source_addresses=props.subnet_workspaces_prefixes,
                            target_fqdns=PermittedDomains.UBUNTU_SNAPCRAFT,
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external RStudio deb downloads",
                            name="AllowRStudioDeb",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=int(Ports.HTTPS),
                                    protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                                ),
                            ],
                            source_addresses=props.subnet_workspaces_prefixes,
                            target_fqdns=PermittedDomains.RSTUDIO_DEB,
                        ),
                    ],
                ),
            ]

            if props.subnet_user_services_software_repositories_prefixes is not None:
                application_rule_collections.append(
                    network.AzureFirewallApplicationRuleCollectionArgs(
                        action=network.AzureFirewallRCActionArgs(
                            type=network.AzureFirewallRCActionType.ALLOW
                        ),
                        name="software-repositories-allow",
                        priority=FirewallPriorities.SRE_USER_SERVICES_SOFTWARE_REPOSITORIES,
                        rules=[
                            network.AzureFirewallApplicationRuleArgs(
                                description="Allow external CRAN package requests",
                                name="AllowCRANPackageDownload",
                                protocols=[
                                    network.AzureFirewallApplicationRuleProtocolArgs(
                                        port=int(Ports.HTTPS),
                                        protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                                    )
                                ],
                                source_addresses=props.subnet_user_services_software_repositories_prefixes,
                                target_fqdns=PermittedDomains.SOFTWARE_REPOSITORIES_R,
                            ),
                            network.AzureFirewallApplicationRuleArgs(
                                description="Allow external PyPI package requests",
                                name="AllowPyPIPackageDownload",
                                protocols=[
                                    network.AzureFirewallApplicationRuleProtocolArgs(
                                        port=int(Ports.HTTPS),
                                        protocol_type=network.AzureFirewallApplicationRuleProtocolType.HTTPS,
                                    )
                                ],
                                source_addresses=props.subnet_user_services_software_repositories_prefixes,
                                target_fqdns=PermittedDomains.SOFTWARE_REPOSITORIES_PYTHON,
                            ),
                        ],
                    )
                )

            if props.subnet_user_services_gitea_mirror_prefixes is not None:
                application_rule_collections.append(
                    network.AzureFirewallApplicationRuleCollectionArgs(
                        action=network.AzureFirewallRCActionArgs(
                            type=network.AzureFirewallRCActionType.ALLOW
                        ),
                        name="user-services-gitea-mirror-allow",
                        priority=FirewallPriorities.SRE_USER_SERVICES_GITEA_MIRROR,
                        rules=[
                            network.AzureFirewallApplicationRuleArgs(
                                description="Allow external GitHub repository update requests",
                                name="AllowGitHubRepositoryUpdates",
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
                                source_addresses=props.subnet_user_services_gitea_mirror_prefixes,
                                target_fqdns=PermittedDomains.SOFTWARE_REPOSITORIES_GITHUB,
                            ),
                        ],
                    )
                )
            application_rule_collections.append(
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(
                        type=network.AzureFirewallRCActionType.DENY
                    ),
                    name="workspaces-deny",
                    priority=FirewallPriorities.SRE_WORKSPACES_DENY,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Deny external Ubuntu Snap Store upload and login access",
                            name="DenyUbuntuSnapcraft",
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
                            source_addresses=props.subnet_workspaces_prefixes,
                            target_fqdns=ForbiddenDomains.UBUNTU_SNAPCRAFT,
                        ),
                    ],
                )
            )
            # Netbird rule
            application_rule_collections.append(
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(
                        type=network.AzureFirewallRCActionType.ALLOW
                    ),
                    name="workspaces-netbird-allow",
                    priority=FirewallPriorities.SRE_WORKSPACES_NETBIRD,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow access to Netbird managment",
                            name="AllowNetbird",
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
                            source_addresses=props.subnet_workspaces_prefixes,
                            target_fqdns=PermittedDomains.NETBIRD_MANAGEMENT,
                        ),
                    ],
                )
            )

        # Deploy firewall
        self.firewall = network.AzureFirewall(
            f"{self._name}_firewall",
            application_rule_collections=application_rule_collections,
            azure_firewall_name=f"{stack_name}-firewall",
            ip_configurations=[
                network.AzureFirewallIPConfigurationArgs(
                    name="FirewallIpConfiguration",
                    public_ip_address=network.SubResourceArgs(id=public_ip.id),
                    subnet=network.SubResourceArgs(id=props.subnet_firewall_id),
                )
            ],
            location=props.location,
            management_ip_configuration=network.AzureFirewallIPConfigurationArgs(
                name="FirewallManagementIpConfiguration",
                public_ip_address=network.SubResourceArgs(id=public_ip_management.id),
                subnet=network.SubResourceArgs(id=props.subnet_firewall_management_id),
            ),
            network_rule_collections=network_rule_collections,
            resource_group_name=props.resource_group_name,
            sku=network.AzureFirewallSkuArgs(
                name=network.AzureFirewallSkuName.AZF_W_V_NET,
                tier=network.AzureFirewallSkuTier.BASIC,
            ),
            opts=child_opts,
            tags=child_tags,
        )

        # Add diagnostic settings for firewall
        # This links the firewall to the log analytics workspace
        monitor.DiagnosticSetting(
            f"{self._name}_firewall_diagnostic_settings",
            name="firewall_diagnostic_settings",
            log_analytics_destination_type="Dedicated",
            logs=[
                {
                    "category_group": "allLogs",
                    "enabled": True,
                    "retention_policy": {
                        "days": 0,
                        "enabled": False,
                    },
                },
            ],
            metrics=[
                {
                    "category": "AllMetrics",
                    "enabled": True,
                    "retention_policy": {
                        "days": 0,
                        "enabled": False,
                    },
                }
            ],
            resource_uri=self.firewall.id,
            workspace_id=props.log_analytics_workspace.id,
        )

        # Retrieve the private IP address for the firewall
        private_ip_address = self.firewall.ip_configurations.apply(
            lambda cfgs: "" if not cfgs else cfgs[0].private_ip_address
        )

        # Route all external traffic through the firewall.
        #
        # We use the system default route "0.0.0.0/0" as this will be overruled by
        # anything more specific, such as VNet <-> VNet traffic which we do not want to
        # send via the firewall.
        #
        # See https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview
        self.route = network.Route(
            f"{self._name}_route_via_firewall",
            address_prefix="0.0.0.0/0",
            next_hop_ip_address=private_ip_address,
            next_hop_type=network.RouteNextHopType.VIRTUAL_APPLIANCE,
            resource_group_name=props.resource_group_name,
            route_name="ViaFirewall",
            route_table_name=props.route_table_name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=self.firewall)
            ),
        )
