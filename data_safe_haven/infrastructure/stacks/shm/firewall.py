"""Pulumi component for SHM traffic routing"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network

from data_safe_haven.infrastructure.common import SREIpRanges, get_id_from_subnet


class SHMFirewallProps:
    """Properties for SHMFirewallComponent"""

    def __init__(
        self,
        domain_controller_private_ip: Input[str],
        dns_zone: Input[network.Zone],
        location: Input[str],
        resource_group_name: Input[str],
        route_table_name: Input[str],
        subnet_firewall: Input[network.GetSubnetResult],
        subnet_identity_servers: Input[network.GetSubnetResult],
        subnet_update_servers: Input[network.GetSubnetResult],
    ) -> None:
        self.domain_controller_private_ip = domain_controller_private_ip
        self.dns_zone_name = Output.from_input(dns_zone).apply(lambda zone: zone.name)
        self.location = location
        self.resource_group_name = resource_group_name
        self.route_table_name = route_table_name
        self.subnet_firewall_id = Output.from_input(subnet_firewall).apply(
            get_id_from_subnet
        )
        self.subnet_identity_servers_iprange = Output.from_input(
            subnet_identity_servers
        ).apply(lambda s: str(s.address_prefix) if s.address_prefix else "")
        self.subnet_update_servers_iprange = Output.from_input(
            subnet_update_servers
        ).apply(lambda s: str(s.address_prefix) if s.address_prefix else "")


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
        ntp_fqdns = [
            "time.google.com",
            "time1.google.com",
            "time2.google.com",
            "time3.google.com",
            "time4.google.com",
        ]
        sre_package_repositories_subnets = [
            str(SREIpRanges(idx).user_services_software_repositories)
            for idx in range(1, SREIpRanges.max_index)
        ]
        sre_remote_desktop_gateway_subnets = [
            str(SREIpRanges(idx).guacamole_containers)
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
                    name=f"{stack_name}-identity-servers",
                    priority=1000,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external operational requests from AzureAD Connect",
                            name="AllowExternalAzureADConnectOperations",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=[props.subnet_identity_servers_iprange],
                            target_fqdns=[
                                "*.blob.core.windows.net",
                                "*.servicebus.windows.net",
                                "aadconnecthealth.azure.com",
                                "adminwebservice.microsoftonline.com",
                                "s1.adhybridhealth.azure.com",
                                "umwatson.events.data.microsoft.com",
                                "v10.events.data.microsoft.com",
                                "v20.events.data.microsoft.com"
                            ],
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external password reset requests from AzureAD Connect",
                            name="AllowExternalAzureADConnectPasswordReset",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=[props.subnet_identity_servers_iprange],
                            target_fqdns=[
                                "*-sb.servicebus.windows.net",
                                "*.servicebus.windows.net",
                                "passwordreset.microsoftonline.com"
                            ],
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external setup requests from AzureAD Connect",
                            name="AllowExternalAzureADConnectSetup",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=[props.subnet_identity_servers_iprange],
                            target_fqdns=[
                                "s1.adhybridhealth.azure.com",
                                "management.azure.com",
                                "policykeyservice.dc.ad.msft.net",
                                "www.office.com",
                            ],
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external AzureAD login requests",
                            name="AllowExternalAzureADLogin",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=[props.subnet_identity_servers_iprange],
                            target_fqdns=[
                                "aadcdn.msftauth.net",
                                "login.live.com",
                                "login.microsoftonline.com",
                                "login.windows.net",
                                "secure.aadcdn.microsoftonline-p.com",
                            ],
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external AzureMFAConnect operational requests",
                            name="AllowExternalAzureMFAConnectOperations",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=[props.subnet_identity_servers_iprange],
                            target_fqdns=[
                                "css.phonefactor.net",
                                "pfd.phonefactor.net",
                                "pfd2.phonefactor.net",
                            ],
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external AzureMFAConnect setup requests",
                            name="AllowExternalAzureMFAConnectSetup",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=[props.subnet_identity_servers_iprange],
                            target_fqdns=[
                                "adnotifications.windowsazure.com",
                                "credentials.azure.com",
                                "strongauthenticationservice.auth.microsoft.com",
                            ],
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external certificate setup requests",
                            name="AllowExternalCertificateStatusCheck",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=[props.subnet_identity_servers_iprange],
                            target_fqdns=[
                                "crl.microsoft.com",
                                "crl3.digicert.com",
                                "crl4.digicert.com",
                                "ocsp.digicert.com",
                            ],
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external script downloads from GitHub",
                            name="AllowExternalGitHubScriptDownload",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=[props.subnet_identity_servers_iprange],
                            target_fqdns=[
                                "raw.githubusercontent.com",
                            ],
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external Powershell module installation requests",
                            name="AllowExternalPowershellModuleInstallation",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=[props.subnet_identity_servers_iprange],
                            target_fqdns=[
                                "psg-prod-eastus.azureedge.net",
                                "www.powershellgallery.com",
                            ],
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external MSOnline connection requests",
                            name="AllowExternalPowershellModuleMSOnlineConnections",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=[props.subnet_update_servers_iprange],
                            target_fqdns=["provisioningapi.microsoftonline.com"],
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external Windows update requests",
                            name="AllowExternalWindowsUpdate",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=80,
                                    protocol_type="Http",
                                ),
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                ),
                            ],
                            source_addresses=[props.subnet_identity_servers_iprange],
                            target_fqdns=[
                                "au.download.windowsupdate.com",
                                "ctldl.windowsupdate.com",
                                "download.microsoft.com",
                                "download.windowsupdate.com",
                                "fe2cr.update.microsoft.com",
                                "fe3cr.delivery.mp.microsoft.com",
                                "geo-prod.do.dsp.mp.microsoft.com",
                                "go.microsoft.com",
                                "ntservicepack.microsoft.com",
                                "onegetcdn.azureedge.net",
                                "settings-win.data.microsoft.com",
                                "slscr.update.microsoft.com",
                                "test.stats.update.microsoft.com",
                                "tlu.dl.delivery.mp.microsoft.com",
                                "umwatson.events.data.microsoft.com",
                                "v10.events.data.microsoft.com",
                                "v10.vortex-win.data.microsoft.com",
                                "v20.events.data.microsoft.com",
                                "windowsupdate.microsoft.com",
                            ],
                        ),
                    ],
                ),
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(type="Allow"),
                    name=f"{stack_name}-any",
                    priority=1010,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external Azure Automation requests",
                            name="AllowExternalAzureAutomationOperations",
                            protocols=[network.AzureFirewallNetworkRuleProtocol.TCP,
                                       network.AzureFirewallNetworkRuleProtocol.UDP],
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
                                    port=123,
                                    protocol_type="Http",
                                )
                            ],
                            source_addresses=["*"],
                            target_fqdns=ntp_fqdns,
                        ),
                    ],
                ),
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(type="Allow"),
                    name=f"{stack_name}-update-servers",
                    priority=1020,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external Linux update requests",
                            name="AllowExternalLinuxUpdate",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=80,
                                    protocol_type="Http",
                                ),
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                ),
                            ],
                            source_addresses=[props.subnet_update_servers_iprange],
                            target_fqdns=[
                                # "apt.postgresql.org",
                                "archive.ubuntu.com",
                                "azure.archive.ubuntu.com",
                                "changelogs.ubuntu.com",
                                "cloudapp.azure.com",  # this is where azure.archive.ubuntu.com is hosted
                                # "d20rj4el6vkp4c.cloudfront.net",
                                # "dbeaver.io",
                                # "packages.gitlab.com",
                                "packages.microsoft.com",
                                # "qgis.org",
                                "security.ubuntu.com",
                                # "ubuntu.qgis.org"
                            ],
                        ),
                    ],
                ),
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(type="Allow"),
                    name=f"{stack_name}-sre-package-repositories",
                    priority=1100,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external CRAN package requests",
                            name="AllowExternalPackageDownloadCRAN",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=sre_package_repositories_subnets,
                            target_fqdns=["cran.r-project.org"],
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external PyPI package requests",
                            name="AllowExternalPackageDownloadPyPI",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=sre_package_repositories_subnets,
                            target_fqdns=["files.pythonhosted.org", "pypi.org"],
                        ),
                    ],
                ),
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(type="Allow"),
                    name=f"{stack_name}-sre-remote-desktop-gateways",
                    priority=1110,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external OAuth login requests",
                            name="AllowExternalOAuthLogin",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                )
                            ],
                            source_addresses=sre_remote_desktop_gateway_subnets,
                            target_fqdns=["login.microsoftonline.com"],
                        ),
                    ],
                ),
                network.AzureFirewallApplicationRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(type="Allow"),
                    name=f"{stack_name}-sre-workspaces",
                    priority=1120,
                    rules=[
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external Linux ClamAV update requests",
                            name="AllowExternalLinuxClamAVUpdate",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=80,
                                    protocol_type="Http",
                                ),
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=443,
                                    protocol_type="Https",
                                ),
                            ],
                            source_addresses=sre_workspaces_subnets,
                            target_fqdns=[
                                "current.cvd.clamav.net",
                                "database.clamav.net.cdn.cloudflare.net",
                                "database.clamav.net",
                            ],
                        ),
                        network.AzureFirewallApplicationRuleArgs(
                            description="Allow external Linux ClamAV update requests",
                            name="AllowExternalUbuntuKeyserver",
                            protocols=[
                                network.AzureFirewallApplicationRuleProtocolArgs(
                                    port=11371,
                                    protocol_type="Http",
                                ),
                            ],
                            source_addresses=sre_workspaces_subnets,
                            target_fqdns=[
                                "keyserver.ubuntu.com",
                            ],
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
                    name=f"{stack_name}-identity-servers",
                    priority=1000,
                    rules=[
                        network.AzureFirewallNetworkRuleArgs(
                            description="Allow external DNS resolver",
                            destination_addresses=[external_dns_resolver],
                            destination_ports=["53"],
                            name="AllowExternalDnsResolver",
                            protocols=[
                                network.AzureFirewallNetworkRuleProtocol.UDP,
                                network.AzureFirewallNetworkRuleProtocol.TCP,
                            ],
                            source_addresses=[props.subnet_identity_servers_iprange],
                        ),
                    ],
                ),
                network.AzureFirewallNetworkRuleCollectionArgs(
                    action=network.AzureFirewallRCActionArgs(type="Allow"),
                    name=f"{stack_name}-all",
                    priority=1010,
                    rules=[
                        network.AzureFirewallNetworkRuleArgs(
                            description="Allow external NTP requests",
                            destination_addresses=ntp_ip_addresses,
                            destination_ports=["123"],
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
        self.ntp_fqdns = ntp_fqdns
        self.ntp_ip_addresses = ntp_ip_addresses
        self.public_ip_id = public_ip.id

        # Register exports
        self.exports = {
            "private_ip_address": private_ip_address,
        }
