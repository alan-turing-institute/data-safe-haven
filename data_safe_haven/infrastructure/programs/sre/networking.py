"""Pulumi component for SRE networking"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, InvokeOptions, Output, ResourceOptions
from pulumi_azure_native import network, provider

from data_safe_haven.functions import alphanumeric, replace_separators
from data_safe_haven.infrastructure.common import (
    SREDnsIpRanges,
    SREIpRanges,
    get_id_from_vnet,
    get_name_from_vnet,
)
from data_safe_haven.types import NetworkingPriorities, Ports


class SRENetworkingProps:
    """Properties for SRENetworkingComponent"""

    def __init__(
        self,
        dns_private_zones: Input[dict[str, network.PrivateZone]],
        dns_server_ip: Input[str],
        dns_virtual_network: Input[network.VirtualNetwork],
        location: Input[str],
        resource_group_name: Input[str],
        shm_fqdn: Input[str],
        shm_location: Input[str],
        shm_resource_group_name: Input[str],
        shm_subscription_id: Input[str],
        shm_zone_name: Input[str],
        sre_name: Input[str],
        user_public_ip_ranges: Input[list[str]],
    ) -> None:
        # Other variables
        self.dns_private_zones = dns_private_zones
        self.dns_virtual_network_id = Output.from_input(dns_virtual_network).apply(
            get_id_from_vnet
        )
        self.dns_virtual_network_name = Output.from_input(dns_virtual_network).apply(
            get_name_from_vnet
        )
        self.dns_server_ip = dns_server_ip
        self.location = location
        self.resource_group_name = resource_group_name
        self.shm_fqdn = shm_fqdn
        self.shm_location = shm_location
        self.shm_resource_group_name = shm_resource_group_name
        self.shm_subscription_id = shm_subscription_id
        self.shm_zone_name = shm_zone_name
        self.sre_name = sre_name
        self.user_public_ip_ranges = user_public_ip_ranges


class SRENetworkingComponent(ComponentResource):
    """Deploy networking with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SRENetworkingProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:NetworkingComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "networking"} | (tags if tags else {})

        # Define route table
        route_table = network.RouteTable(
            f"{self._name}_route_table",
            location=props.location,
            resource_group_name=props.resource_group_name,
            route_table_name=f"{stack_name}-route-table",
            routes=[],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=["routes"]
                ),  # allow routes to be created outside this definition
            ),
            tags=child_tags,
        )

        # Define NSGs
        nsg_application_gateway = network.NetworkSecurityGroup(
            f"{self._name}_nsg_application_gateway",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-application-gateway",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound gateway management service traffic.",
                    destination_address_prefix="*",
                    destination_port_ranges=["65200-65535"],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowGatewayManagerServiceInbound",
                    priority=NetworkingPriorities.AZURE_GATEWAY_MANAGER,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix="GatewayManager",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound Azure load balancer traffic.",
                    destination_address_prefix="*",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowAzureLoadBalancerServiceInbound",
                    priority=NetworkingPriorities.AZURE_LOAD_BALANCER,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="AzureLoadBalancer",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from users over the internet.",
                    destination_address_prefix=SREIpRanges.application_gateway.prefix,
                    destination_port_ranges=[Ports.HTTP, Ports.HTTPS],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowUsersInternetInbound",
                    priority=NetworkingPriorities.AUTHORISED_EXTERNAL_USER_IPS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefixes=props.user_public_ip_ranges,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from from ssllabs.com for SSL quality reporting.",
                    destination_address_prefix=SREIpRanges.application_gateway.prefix,
                    destination_port_ranges=[Ports.HTTPS],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowSslLabsInternetInbound",
                    priority=NetworkingPriorities.AUTHORISED_EXTERNAL_SSL_LABS_IPS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix="64.41.200.0/24",
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
                # Attempting to add our standard DenyAzurePlatformDnsOutbound rule will
                # cause this NSG to fail validation. More details here:
                # https://learn.microsoft.com/en-us/azure/application-gateway/configuration-infrastructure#network-security-groups
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to DNS servers.",
                    destination_address_prefix=SREDnsIpRanges.vnet.prefix,
                    destination_port_ranges=[Ports.DNS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.application_gateway.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to the Guacamole remote desktop gateway.",
                    destination_address_prefix=SREIpRanges.guacamole_containers.prefix,
                    destination_port_ranges=[Ports.HTTP],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowGuacamoleContainersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_GUACAMOLE_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.application_gateway.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound gateway management traffic over the internet.",
                    destination_address_prefix="Internet",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowGatewayManagerInternetOutbound",
                    priority=NetworkingPriorities.EXTERNAL_INTERNET,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
                    source_port_range="*",
                ),
                # Attempting to add our standard DenyAllOtherOutbound rule will cause
                # this NSG to fail validation. More details here:
                # https://learn.microsoft.com/en-us/azure/application-gateway/configuration-infrastructure#network-security-groups
            ],
            opts=child_opts,
            tags=child_tags,
        )
        nsg_apt_proxy_server = network.NetworkSecurityGroup(
            f"{self._name}_nsg_apt_proxy_server",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-apt-proxy-server",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from SRE workspaces.",
                    destination_address_prefix=SREIpRanges.apt_proxy_server.prefix,
                    destination_port_ranges=[Ports.LINUX_UPDATE],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowWorkspacesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
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
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny outbound connections to Azure Platform DNS endpoints (including 168.63.129.16), which are not included in the 'Internet' service tag.",
                    destination_address_prefix="AzurePlatformDNS",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAzurePlatformDnsOutbound",
                    priority=NetworkingPriorities.AZURE_PLATFORM_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to DNS servers.",
                    destination_address_prefix=SREDnsIpRanges.vnet.prefix,
                    destination_port_ranges=[Ports.DNS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.apt_proxy_server.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to configuration data endpoints.",
                    destination_address_prefix=SREIpRanges.data_configuration.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataConfigurationEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_CONFIGURATION,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.apt_proxy_server.prefix,
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
                    source_address_prefix=SREIpRanges.apt_proxy_server.prefix,
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
        nsg_clamav_mirror = network.NetworkSecurityGroup(
            f"{self._name}_nsg_clamav_mirror",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-clamav-mirror",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from SRE workspaces.",
                    destination_address_prefix=SREIpRanges.clamav_mirror.prefix,
                    destination_port_ranges=[Ports.HTTP, Ports.HTTPS, Ports.SQUID],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowWorkspacesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
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
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny outbound connections to Azure Platform DNS endpoints (including 168.63.129.16), which are not included in the 'Internet' service tag.",
                    destination_address_prefix="AzurePlatformDNS",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAzurePlatformDnsOutbound",
                    priority=NetworkingPriorities.AZURE_PLATFORM_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to DNS servers.",
                    destination_address_prefix=SREDnsIpRanges.vnet.prefix,
                    destination_port_ranges=[Ports.DNS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.clamav_mirror.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to configuration data endpoints.",
                    destination_address_prefix=SREIpRanges.data_configuration.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataConfigurationEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_CONFIGURATION,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.clamav_mirror.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to ClamAV repositories over the internet.",
                    destination_address_prefix="Internet",
                    destination_port_ranges=[Ports.HTTP, Ports.HTTPS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowClamAVDefinitionsInternetOutbound",
                    priority=NetworkingPriorities.EXTERNAL_INTERNET,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.clamav_mirror.prefix,
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
        nsg_data_configuration = network.NetworkSecurityGroup(
            f"{self._name}_nsg_data_configuration",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-data-configuration",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from Guacamole remote desktop gateway.",
                    destination_address_prefix=SREIpRanges.data_configuration.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowGuacamoleContainersInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_GUACAMOLE_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.guacamole_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from identity containers.",
                    destination_address_prefix=SREIpRanges.data_configuration.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowIdentityServersInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_IDENTITY_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.identity_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from user services containers.",
                    destination_address_prefix=SREIpRanges.data_configuration.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowUserServicesContainersInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.user_services_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from user services software repositories.",
                    destination_address_prefix=SREIpRanges.data_configuration.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowUserServicesSoftwareRepositoriesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_SOFTWARE_REPOSITORIES,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.user_services_software_repositories.prefix,
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
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny outbound connections to Azure Platform DNS endpoints (including 168.63.129.16), which are not included in the 'Internet' service tag.",
                    destination_address_prefix="AzurePlatformDNS",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAzurePlatformDnsOutbound",
                    priority=NetworkingPriorities.AZURE_PLATFORM_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
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
        nsg_desired_state = network.NetworkSecurityGroup(
            f"{self._name}_nsg_desired_state",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-desired-state",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from workspaces.",
                    destination_address_prefix=SREIpRanges.data_configuration.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowWorkspacesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
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
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny outbound connections to Azure Platform DNS endpoints (including 168.63.129.16), which are not included in the 'Internet' service tag.",
                    destination_address_prefix="AzurePlatformDNS",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAzurePlatformDnsOutbound",
                    priority=NetworkingPriorities.AZURE_PLATFORM_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
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
        nsg_data_private = network.NetworkSecurityGroup(
            f"{self._name}_nsg_data_private",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-data-private",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from SRE workspaces.",
                    destination_address_prefix=SREIpRanges.data_private.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowWorkspacesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
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
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny outbound connections to Azure Platform DNS endpoints (including 168.63.129.16), which are not included in the 'Internet' service tag.",
                    destination_address_prefix="AzurePlatformDNS",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAzurePlatformDnsOutbound",
                    priority=NetworkingPriorities.AZURE_PLATFORM_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
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
        nsg_guacamole_containers = network.NetworkSecurityGroup(
            f"{self._name}_nsg_guacamole_containers",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-guacamole-containers",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from the Application Gateway.",
                    destination_address_prefix=SREIpRanges.guacamole_containers.prefix,
                    destination_port_ranges=[Ports.HTTP],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowApplicationGatewayInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_APPLICATION_GATEWAY,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.application_gateway.prefix,
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
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny outbound connections to Azure Platform DNS endpoints (including 168.63.129.16), which are not included in the 'Internet' service tag.",
                    destination_address_prefix="AzurePlatformDNS",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAzurePlatformDnsOutbound",
                    priority=NetworkingPriorities.AZURE_PLATFORM_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to DNS servers.",
                    destination_address_prefix=SREDnsIpRanges.vnet.prefix,
                    destination_port_ranges=[Ports.DNS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.guacamole_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to configuration data endpoints.",
                    destination_address_prefix=SREIpRanges.data_configuration.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataConfigurationEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_CONFIGURATION,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.guacamole_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to Guacamole support services.",
                    destination_address_prefix=SREIpRanges.guacamole_containers_support.prefix,
                    destination_port_ranges=[Ports.POSTGRESQL],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowGuacamoleContainersSupportOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_GUACAMOLE_CONTAINERS_SUPPORT,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.guacamole_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow LDAP client requests over TCP.",
                    destination_address_prefix=SREIpRanges.identity_containers.prefix,
                    destination_port_ranges=[Ports.LDAP_APRICOT],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowIdentityServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_IDENTITY_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.guacamole_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to SRE workspaces.",
                    destination_address_prefix=SREIpRanges.workspaces.prefix,
                    destination_port_ranges=[Ports.SSH, Ports.RDP],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowWorkspacesOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.guacamole_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound OAuth connections over the internet.",
                    destination_address_prefix="Internet",
                    destination_port_ranges=[Ports.HTTP, Ports.HTTPS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowOAuthInternetOutbound",
                    priority=NetworkingPriorities.EXTERNAL_INTERNET,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.guacamole_containers.prefix,
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
        nsg_guacamole_containers_support = network.NetworkSecurityGroup(
            f"{self._name}_nsg_guacamole_containers_support",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-guacamole-containers-support",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from Guacamole remote desktop gateway.",
                    destination_address_prefix=SREIpRanges.guacamole_containers_support.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowGuacamoleContainersInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_GUACAMOLE_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.guacamole_containers.prefix,
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
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny outbound connections to Azure Platform DNS endpoints (including 168.63.129.16), which are not included in the 'Internet' service tag.",
                    destination_address_prefix="AzurePlatformDNS",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAzurePlatformDnsOutbound",
                    priority=NetworkingPriorities.AZURE_PLATFORM_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
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
        nsg_identity_containers = network.NetworkSecurityGroup(
            f"{self._name}_nsg_identity_containers",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-identity-containers",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow LDAP client requests from Guacamole over TCP.",
                    destination_address_prefix=SREIpRanges.identity_containers.prefix,
                    destination_port_ranges=[Ports.LDAP_APRICOT],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowGuacamoleLDAPClientTCPInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_GUACAMOLE_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.guacamole_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow LDAP client requests from user services over TCP.",
                    destination_address_prefix=SREIpRanges.identity_containers.prefix,
                    destination_port_ranges=[Ports.LDAP_APRICOT],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowUserServicesLDAPClientTCPInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.user_services_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow LDAP client requests from workspaces over TCP.",
                    destination_address_prefix=SREIpRanges.identity_containers.prefix,
                    destination_port_ranges=[Ports.LDAP_APRICOT],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowWorkspaceLDAPClientTCPInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
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
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny outbound connections to Azure Platform DNS endpoints (including 168.63.129.16), which are not included in the 'Internet' service tag.",
                    destination_address_prefix="AzurePlatformDNS",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAzurePlatformDnsOutbound",
                    priority=NetworkingPriorities.AZURE_PLATFORM_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to DNS servers.",
                    destination_address_prefix=SREDnsIpRanges.vnet.prefix,
                    destination_port_ranges=[Ports.DNS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.identity_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to configuration data endpoints.",
                    destination_address_prefix=SREIpRanges.data_configuration.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataConfigurationEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_CONFIGURATION,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.identity_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound OAuth connections over the internet.",
                    destination_address_prefix="Internet",
                    destination_port_ranges=[Ports.HTTP, Ports.HTTPS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowOAuthInternetOutbound",
                    priority=NetworkingPriorities.EXTERNAL_INTERNET,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.identity_containers.prefix,
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
        nsg_monitoring = network.NetworkSecurityGroup(
            f"{self._name}_nsg_monitoring",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-monitoring",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from own subnet.",
                    destination_address_prefix=SREIpRanges.monitoring.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowMonitoringToolsInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_SELF,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.monitoring.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from workspaces.",
                    destination_address_prefix=SREIpRanges.monitoring.prefix,
                    destination_port_ranges=[Ports.HTTPS],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowWorkspacesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
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
                    description="Allow outbound connections to own subnet.",
                    destination_address_prefix=SREIpRanges.monitoring.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowMonitoringToolsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_SELF,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.monitoring.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to workspaces.",
                    destination_address_prefix=SREIpRanges.workspaces.prefix,
                    destination_port_ranges=[Ports.AZURE_MONITORING],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowWorkspacesOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.monitoring.prefix,
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
        nsg_user_services_containers = network.NetworkSecurityGroup(
            f"{self._name}_nsg_user_services_containers",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-user-services-containers",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from SRE workspaces.",
                    destination_address_prefix=SREIpRanges.user_services_containers.prefix,
                    destination_port_ranges=[Ports.SSH, Ports.HTTP, Ports.HTTPS],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowWorkspacesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
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
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny outbound connections to Azure Platform DNS endpoints (including 168.63.129.16), which are not included in the 'Internet' service tag.",
                    destination_address_prefix="AzurePlatformDNS",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAzurePlatformDnsOutbound",
                    priority=NetworkingPriorities.AZURE_PLATFORM_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to DNS servers.",
                    destination_address_prefix=SREDnsIpRanges.vnet.prefix,
                    destination_port_ranges=[Ports.DNS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.user_services_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to configuration data endpoints.",
                    destination_address_prefix=SREIpRanges.data_configuration.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataConfigurationEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_CONFIGURATION,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.user_services_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow LDAP client requests over TCP.",
                    destination_address_prefix=SREIpRanges.identity_containers.prefix,
                    destination_port_ranges=[Ports.LDAP_APRICOT],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowIdentityServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_IDENTITY_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.user_services_containers.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to container support services.",
                    destination_address_prefix=SREIpRanges.user_services_containers_support.prefix,
                    destination_port_ranges=[Ports.POSTGRESQL],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowUserServicesContainersSupportOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_CONTAINERS_SUPPORT,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.user_services_containers.prefix,
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
        nsg_user_services_containers_support = network.NetworkSecurityGroup(
            f"{self._name}_nsg_user_services_containers_support",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-user-services-containers-support",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from user services containers.",
                    destination_address_prefix=SREIpRanges.user_services_containers_support.prefix,
                    destination_port_ranges=[Ports.POSTGRESQL],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowUserServicesContainersInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.user_services_containers.prefix,
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
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny outbound connections to Azure Platform DNS endpoints (including 168.63.129.16), which are not included in the 'Internet' service tag.",
                    destination_address_prefix="AzurePlatformDNS",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAzurePlatformDnsOutbound",
                    priority=NetworkingPriorities.AZURE_PLATFORM_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
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
        nsg_user_services_databases = network.NetworkSecurityGroup(
            f"{self._name}_nsg_user_services_databases",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-user-services-databases",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from SRE workspaces.",
                    destination_address_prefix=SREIpRanges.user_services_databases.prefix,
                    destination_port_ranges=[Ports.MSSQL, Ports.POSTGRESQL],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowWorkspacesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
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
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny outbound connections to Azure Platform DNS endpoints (including 168.63.129.16), which are not included in the 'Internet' service tag.",
                    destination_address_prefix="AzurePlatformDNS",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAzurePlatformDnsOutbound",
                    priority=NetworkingPriorities.AZURE_PLATFORM_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to DNS servers.",
                    destination_address_prefix=SREDnsIpRanges.vnet.prefix,
                    destination_port_ranges=[Ports.DNS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.user_services_databases.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to configuration data endpoints.",
                    destination_address_prefix=SREIpRanges.data_configuration.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataConfigurationEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_CONFIGURATION,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.user_services_databases.prefix,
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
        nsg_user_services_software_repositories = network.NetworkSecurityGroup(
            f"{self._name}_nsg_user_services_software_repositories",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-user-services-software-repositories",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from SRE workspaces.",
                    destination_address_prefix=SREIpRanges.user_services_software_repositories.prefix,
                    destination_port_ranges=[Ports.HTTP, Ports.HTTPS, Ports.SQUID],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowWorkspacesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
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
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny outbound connections to Azure Platform DNS endpoints (including 168.63.129.16), which are not included in the 'Internet' service tag.",
                    destination_address_prefix="AzurePlatformDNS",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAzurePlatformDnsOutbound",
                    priority=NetworkingPriorities.AZURE_PLATFORM_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to DNS servers.",
                    destination_address_prefix=SREDnsIpRanges.vnet.prefix,
                    destination_port_ranges=[Ports.DNS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.user_services_software_repositories.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to configuration data endpoints.",
                    destination_address_prefix=SREIpRanges.data_configuration.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataConfigurationEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_CONFIGURATION,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.user_services_software_repositories.prefix,
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
                    source_address_prefix=SREIpRanges.user_services_software_repositories.prefix,
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
        nsg_workspaces = network.NetworkSecurityGroup(
            f"{self._name}_nsg_workspaces",
            location=props.location,
            network_security_group_name=f"{stack_name}-nsg-workspaces",
            resource_group_name=props.resource_group_name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from monitoring tools.",
                    destination_address_prefix=SREIpRanges.workspaces.prefix,
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
                    description="Allow inbound connections from Guacamole remote desktop gateway.",
                    destination_address_prefix=SREIpRanges.workspaces.prefix,
                    destination_port_ranges=[Ports.SSH, Ports.RDP],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowGuacamoleContainersInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_GUACAMOLE_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.guacamole_containers.prefix,
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
                    access=network.SecurityRuleAccess.DENY,
                    description="Deny outbound connections to Azure Platform DNS endpoints (including 168.63.129.16), which are not included in the 'Internet' service tag.",
                    destination_address_prefix="AzurePlatformDNS",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="DenyAzurePlatformDnsOutbound",
                    priority=NetworkingPriorities.AZURE_PLATFORM_DNS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix="*",
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to ClamAV mirror.",
                    destination_address_prefix=SREIpRanges.clamav_mirror.prefix,
                    destination_port_ranges=[Ports.HTTP],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowClamAVMirrorOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_CLAMAV_MIRROR,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow LDAP client requests over TCP.",
                    destination_address_prefix=SREIpRanges.identity_containers.prefix,
                    destination_port_ranges=[Ports.LDAP_APRICOT],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowIdentityServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_IDENTITY_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to DNS servers.",
                    destination_address_prefix=SREDnsIpRanges.vnet.prefix,
                    destination_port_ranges=[Ports.DNS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to private data endpoints.",
                    destination_address_prefix=SREIpRanges.data_private.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataPrivateEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_PRIVATE,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to desired state data endpoints.",
                    destination_address_prefix=SREIpRanges.desired_state.prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataDesiredStateEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_DESIRED_STATE,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
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
                    source_address_prefix=SREIpRanges.workspaces.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to user services containers.",
                    destination_address_prefix=SREIpRanges.user_services_containers.prefix,
                    destination_port_ranges=[Ports.SSH, Ports.HTTP, Ports.HTTPS],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowUserServicesContainersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to user services databases.",
                    destination_address_prefix=SREIpRanges.user_services_databases.prefix,
                    destination_port_ranges=[Ports.MSSQL, Ports.POSTGRESQL],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowUserServicesDatabasesOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_DATABASES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to user services software repositories.",
                    destination_address_prefix=SREIpRanges.user_services_software_repositories.prefix,
                    destination_port_ranges=[Ports.HTTP, Ports.HTTPS, Ports.SQUID],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowUserServicesSoftwareRepositoriesOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_SOFTWARE_REPOSITORIES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to apt proxy server.",
                    destination_address_prefix=SREIpRanges.apt_proxy_server.prefix,
                    destination_port_ranges=[Ports.LINUX_UPDATE],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowAptProxyServerOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_APT_PROXY_SERVER,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound configuration traffic over the internet.",
                    destination_address_prefix="Internet",
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowConfigurationInternetOutbound",
                    priority=NetworkingPriorities.EXTERNAL_INTERNET,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=SREIpRanges.workspaces.prefix,
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

        # Define the virtual network and its subnets
        # Note that these names for AzureFirewall subnets are required by Azure
        subnet_application_gateway_name = "ApplicationGatewaySubnet"
        subnet_apt_proxy_server_name = "AptProxyServerSubnet"
        subnet_clamav_mirror_name = "ClamAVMirrorSubnet"
        subnet_data_configuration_name = "DataConfigurationSubnet"
        subnet_desired_state_name = "DataDesiredStateSubnet"
        subnet_data_private_name = "DataPrivateSubnet"
        subnet_firewall_name = "AzureFirewallSubnet"
        subnet_firewall_management_name = "AzureFirewallManagementSubnet"
        subnet_guacamole_containers_name = "GuacamoleContainersSubnet"
        subnet_guacamole_containers_support_name = "GuacamoleContainersSupportSubnet"
        subnet_identity_containers_name = "IdentityContainersSubnet"
        subnet_monitoring_name = "MonitoringSubnet"
        subnet_user_services_containers_name = "UserServicesContainersSubnet"
        subnet_user_services_containers_support_name = (
            "UserServicesContainersSupportSubnet"
        )
        subnet_user_services_databases_name = "UserServicesDatabasesSubnet"
        subnet_user_services_software_repositories_name = (
            "UserServicesSoftwareRepositoriesSubnet"
        )
        subnet_workspaces_name = "WorkspacesSubnet"
        sre_virtual_network = network.VirtualNetwork(
            f"{self._name}_virtual_network",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[SREIpRanges.vnet.prefix],
            ),
            dhcp_options=network.DhcpOptionsArgs(dns_servers=[props.dns_server_ip]),
            location=props.location,
            resource_group_name=props.resource_group_name,
            # Note that we define subnets inline to avoid creation order issues
            subnets=[
                # Application gateway subnet
                network.SubnetArgs(
                    address_prefix=SREIpRanges.application_gateway.prefix,
                    name=subnet_application_gateway_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_application_gateway.id
                    ),
                    route_table=None,  # the application gateway must not go via the firewall
                ),
                # apt proxy server
                network.SubnetArgs(
                    address_prefix=SREIpRanges.apt_proxy_server.prefix,
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name=subnet_apt_proxy_server_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_apt_proxy_server.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # ClamAV mirror
                network.SubnetArgs(
                    address_prefix=SREIpRanges.clamav_mirror.prefix,
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name=subnet_clamav_mirror_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_clamav_mirror.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # Configuration data subnet
                network.SubnetArgs(
                    address_prefix=SREIpRanges.data_configuration.prefix,
                    name=subnet_data_configuration_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_data_configuration.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                    service_endpoints=[
                        network.ServiceEndpointPropertiesFormatArgs(
                            locations=[props.location],
                            service="Microsoft.Storage",
                        )
                    ],
                ),
                # Desired state data subnet
                network.SubnetArgs(
                    address_prefix=SREIpRanges.desired_state.prefix,
                    name=subnet_desired_state_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_desired_state.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                    service_endpoints=[
                        network.ServiceEndpointPropertiesFormatArgs(
                            locations=[props.location],
                            service="Microsoft.Storage",
                        )
                    ],
                ),
                # Private data subnet
                network.SubnetArgs(
                    address_prefix=SREIpRanges.data_private.prefix,
                    name=subnet_data_private_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_data_private.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                    service_endpoints=[
                        network.ServiceEndpointPropertiesFormatArgs(
                            locations=[props.location],
                            service="Microsoft.Storage",
                        )
                    ],
                ),
                # Firewall
                network.SubnetArgs(
                    address_prefix=SREIpRanges.firewall.prefix,
                    name=subnet_firewall_name,
                    # Note that NSGs cannot be attached to a subnet containing a firewall
                ),
                # Firewall management
                network.SubnetArgs(
                    address_prefix=SREIpRanges.firewall_management.prefix,
                    name=subnet_firewall_management_name,
                    # Note that NSGs cannot be attached to a subnet containing a firewall
                ),
                # Guacamole containers
                network.SubnetArgs(
                    address_prefix=SREIpRanges.guacamole_containers.prefix,
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name=subnet_guacamole_containers_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_guacamole_containers.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # Guacamole containers support
                network.SubnetArgs(
                    address_prefix=SREIpRanges.guacamole_containers_support.prefix,
                    name=subnet_guacamole_containers_support_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_guacamole_containers_support.id
                    ),
                    private_endpoint_network_policies=network.VirtualNetworkPrivateEndpointNetworkPolicies.ENABLED,
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # Identity containers
                network.SubnetArgs(
                    address_prefix=SREIpRanges.identity_containers.prefix,
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name=subnet_identity_containers_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_identity_containers.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # Monitoring
                network.SubnetArgs(
                    address_prefix=SREIpRanges.monitoring.prefix,
                    name=subnet_monitoring_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_monitoring.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # User services containers
                network.SubnetArgs(
                    address_prefix=SREIpRanges.user_services_containers.prefix,
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name=subnet_user_services_containers_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_user_services_containers.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # User services containers support
                network.SubnetArgs(
                    address_prefix=SREIpRanges.user_services_containers_support.prefix,
                    name=subnet_user_services_containers_support_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_user_services_containers_support.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # User services databases
                network.SubnetArgs(
                    address_prefix=SREIpRanges.user_services_databases.prefix,
                    name=subnet_user_services_databases_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_user_services_databases.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # User services software repositories
                network.SubnetArgs(
                    address_prefix=SREIpRanges.user_services_software_repositories.prefix,
                    delegations=[
                        network.DelegationArgs(
                            name="SubnetDelegationContainerGroups",
                            service_name="Microsoft.ContainerInstance/containerGroups",
                            type="Microsoft.Network/virtualNetworks/subnets/delegations",
                        ),
                    ],
                    name=subnet_user_services_software_repositories_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_user_services_software_repositories.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # Workspaces
                network.SubnetArgs(
                    address_prefix=SREIpRanges.workspaces.prefix,
                    name=subnet_workspaces_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_workspaces.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
            ],
            virtual_network_name=f"{stack_name}-vnet",
            virtual_network_peerings=[],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    ignore_changes=["virtual_network_peerings"]
                ),  # allow peering to SHM virtual network
            ),
            tags=child_tags,
        )

        # Peer the SRE virtual network to the DNS virtual network
        network.VirtualNetworkPeering(
            f"{self._name}_sre_to_dns_peering",
            remote_virtual_network=network.SubResourceArgs(
                id=props.dns_virtual_network_id
            ),
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
            virtual_network_peering_name=Output.concat(
                "peer_sre_", props.sre_name, "_to_dns"
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=sre_virtual_network)
            ),
        )
        network.VirtualNetworkPeering(
            f"{self._name}_dns_to_sre_peering",
            remote_virtual_network=network.SubResourceArgs(id=sre_virtual_network.id),
            resource_group_name=props.resource_group_name,
            virtual_network_name=props.dns_virtual_network_name,
            virtual_network_peering_name=Output.concat(
                "peer_dns_to_sre_", props.sre_name
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=sre_virtual_network)
            ),
        )

        # Define SRE DNS zone
        shm_provider = provider.Provider(
            "shm_provider",
            provider.ProviderArgs(
                location=props.shm_location,
                subscription_id=props.shm_subscription_id,
            ),
        )
        shm_dns_zone = Output.all(
            resource_group_name=props.shm_resource_group_name,
            zone_name=props.shm_zone_name,
        ).apply(
            lambda kwargs: network.get_zone(
                resource_group_name=kwargs["resource_group_name"],
                zone_name=kwargs["zone_name"],
                opts=InvokeOptions(
                    provider=shm_provider,
                ),
            )
        )
        sre_subdomain = Output.from_input(props.sre_name).apply(
            lambda name: alphanumeric(name).lower()
        )
        sre_fqdn = Output.concat(sre_subdomain, ".", props.shm_fqdn)
        sre_dns_zone = network.Zone(
            f"{self._name}_dns_zone",
            location="Global",
            resource_group_name=props.resource_group_name,
            zone_name=sre_fqdn,
            zone_type=network.ZoneType.PUBLIC,
            opts=child_opts,
            tags=child_tags,
        )
        shm_ns_record = network.RecordSet(
            f"{self._name}_ns_record",
            ns_records=sre_dns_zone.name_servers.apply(
                lambda servers: [network.NsRecordArgs(nsdname=ns) for ns in servers]
            ),
            record_type="NS",
            relative_record_set_name=sre_subdomain,
            resource_group_name=props.shm_resource_group_name,
            ttl=3600,
            zone_name=shm_dns_zone.name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    parent=sre_dns_zone,
                    provider=shm_provider,
                ),
            ),
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
            resource_group_name=props.resource_group_name,
            ttl=30,
            zone_name=sre_dns_zone.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=sre_dns_zone)
            ),
        )

        # Define SRE internal DNS zone
        sre_private_dns_zone = network.PrivateZone(
            f"{self._name}_private_zone",
            location="Global",
            private_zone_name=Output.concat("privatelink.", sre_fqdn),
            resource_group_name=props.resource_group_name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=sre_dns_zone)
            ),
            tags=child_tags,
        )

        # Link SRE private DNS zone to DNS virtual network
        network.VirtualNetworkLink(
            f"{self._name}_private_zone_internal_vnet_link",
            location="Global",
            private_zone_name=sre_private_dns_zone.name,
            registration_enabled=False,
            resource_group_name=props.resource_group_name,
            virtual_network=network.SubResourceArgs(id=props.dns_virtual_network_id),
            virtual_network_link_name=Output.concat(
                "link-to-", props.dns_virtual_network_name
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=sre_private_dns_zone)
            ),
        )

        # Link Azure private DNS zones to virtual network
        # Note that although the DNS virtual network is already linked to these zones,
        # Azure Container Instances do not have an IP address during deployment and so
        # must use default Azure DNS when setting up file mounts. This means that we
        # need to be able to resolve the "Storage Account" private DNS zones.
        for dns_zone_name, private_dns_zone in props.dns_private_zones.items():
            network.VirtualNetworkLink(
                replace_separators(
                    f"{self._name}_private_zone_{dns_zone_name}_vnet_link", "_"
                ),
                location="Global",
                private_zone_name=private_dns_zone.name,
                registration_enabled=False,
                resource_group_name=props.resource_group_name,
                virtual_network=network.SubResourceArgs(id=sre_virtual_network.id),
                virtual_network_link_name=Output.concat(
                    "link-to-", sre_virtual_network.name
                ),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=sre_virtual_network)
                ),
                tags=child_tags,
            )

        # Register outputs
        self.route_table_name = route_table.name
        self.shm_ns_record = shm_ns_record
        self.sre_fqdn = sre_dns_zone.name
        self.sre_private_dns_zone = sre_private_dns_zone
        self.subnet_application_gateway = network.get_subnet_output(
            subnet_name=subnet_application_gateway_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_apt_proxy_server = network.get_subnet_output(
            subnet_name=subnet_apt_proxy_server_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_clamav_mirror = network.get_subnet_output(
            subnet_name=subnet_clamav_mirror_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_data_configuration = network.get_subnet_output(
            subnet_name=subnet_data_configuration_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_desired_state = network.get_subnet_output(
            subnet_name=subnet_desired_state_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_desired_state = network.get_subnet_output(
            subnet_name=subnet_desired_state_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_data_private = network.get_subnet_output(
            subnet_name=subnet_data_private_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_firewall = network.get_subnet_output(
            subnet_name=subnet_firewall_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_firewall_management = network.get_subnet_output(
            subnet_name=subnet_firewall_management_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_guacamole_containers = network.get_subnet_output(
            subnet_name=subnet_guacamole_containers_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_guacamole_containers_support = network.get_subnet_output(
            subnet_name=subnet_guacamole_containers_support_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_identity_containers = network.get_subnet_output(
            subnet_name=subnet_identity_containers_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_monitoring = network.get_subnet_output(
            subnet_name=subnet_monitoring_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_user_services_containers = network.get_subnet_output(
            subnet_name=subnet_user_services_containers_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_user_services_containers_support = network.get_subnet_output(
            subnet_name=subnet_user_services_containers_support_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_user_services_databases = network.get_subnet_output(
            subnet_name=subnet_user_services_databases_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_user_services_software_repositories = network.get_subnet_output(
            subnet_name=subnet_user_services_software_repositories_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_workspaces = network.get_subnet_output(
            subnet_name=subnet_workspaces_name,
            resource_group_name=props.resource_group_name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.virtual_network = sre_virtual_network
