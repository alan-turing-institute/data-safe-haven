"""Pulumi component for SRE networking"""
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

from data_safe_haven.functions import alphanumeric, ordered_private_dns_zones
from data_safe_haven.pulumi.common import (
    NetworkingPriorities,
    SREDnsIpRanges,
    SREIpRanges,
    get_id_from_vnet,
    get_name_from_vnet,
)


class SRENetworkingProps:
    """Properties for SRENetworkingComponent"""

    def __init__(
        self,
        dns_resource_group_name: Input[str],
        dns_server_ip: Input[str],
        dns_virtual_network: Input[network.VirtualNetwork],
        firewall_ip_address: Input[str],
        location: Input[str],
        shm_fqdn: Input[str],
        shm_networking_resource_group_name: Input[str],
        shm_subnet_identity_servers_prefix: Input[str],
        shm_subnet_monitoring_prefix: Input[str],
        shm_subnet_update_servers_prefix: Input[str],
        shm_virtual_network_name: Input[str],
        shm_zone_name: Input[str],
        sre_index: Input[int],
        sre_name: Input[str],
        user_public_ip_ranges: Input[list[str]],
    ) -> None:
        # Virtual network and subnet IP ranges
        subnet_ranges = Output.from_input(sre_index).apply(lambda idx: SREIpRanges(idx))
        self.dns_servers_iprange = SREDnsIpRanges().vnet
        self.vnet_iprange = subnet_ranges.apply(lambda s: s.vnet)
        self.subnet_application_gateway_iprange = subnet_ranges.apply(
            lambda s: s.application_gateway
        )
        self.subnet_data_configuration_iprange = subnet_ranges.apply(
            lambda s: s.data_configuration
        )
        self.subnet_data_private_iprange = subnet_ranges.apply(lambda s: s.data_private)
        self.subnet_guacamole_containers_iprange = subnet_ranges.apply(
            lambda s: s.guacamole_containers
        )
        self.subnet_guacamole_containers_support_iprange = subnet_ranges.apply(
            lambda s: s.guacamole_containers_support
        )
        self.subnet_user_services_containers_iprange = subnet_ranges.apply(
            lambda s: s.user_services_containers
        )
        self.subnet_user_services_containers_support_iprange = subnet_ranges.apply(
            lambda s: s.user_services_containers_support
        )
        self.subnet_user_services_databases_iprange = subnet_ranges.apply(
            lambda s: s.user_services_databases
        )
        self.subnet_user_services_software_repositories_iprange = subnet_ranges.apply(
            lambda s: s.user_services_software_repositories
        )
        self.subnet_workspaces_iprange = subnet_ranges.apply(lambda s: s.workspaces)
        # Other variables
        self.dns_resource_group_name = dns_resource_group_name
        self.dns_virtual_network_id = Output.from_input(dns_virtual_network).apply(
            get_id_from_vnet
        )
        self.dns_virtual_network_name = Output.from_input(dns_virtual_network).apply(
            get_name_from_vnet
        )
        self.dns_server_ip = dns_server_ip
        self.firewall_ip_address = firewall_ip_address
        self.location = location
        self.user_public_ip_ranges = user_public_ip_ranges
        self.shm_fqdn = shm_fqdn
        self.shm_networking_resource_group_name = shm_networking_resource_group_name
        self.shm_subnet_identity_servers_prefix = shm_subnet_identity_servers_prefix
        self.shm_subnet_monitoring_prefix = shm_subnet_monitoring_prefix
        self.shm_subnet_update_servers_prefix = shm_subnet_update_servers_prefix
        self.shm_virtual_network_name = shm_virtual_network_name
        self.shm_zone_name = shm_zone_name
        self.sre_name = sre_name


class SRENetworkingComponent(ComponentResource):
    """Deploy networking with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SRENetworkingProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:NetworkingComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-networking",
            opts=child_opts,
        )

        # Define route table
        route_table = network.RouteTable(
            f"{self._name}_route_table",
            location=props.location,
            resource_group_name=resource_group.name,
            route_table_name=f"{stack_name}-route",
            routes=[
                network.RouteArgs(
                    address_prefix="0.0.0.0/0",
                    name="ViaFirewall",
                    next_hop_ip_address=props.firewall_ip_address,
                    next_hop_type=network.RouteNextHopType.VIRTUAL_APPLIANCE,
                ),
            ],
            opts=child_opts,
        )

        # Set address prefixes from ranges
        dns_servers_prefix = str(props.dns_servers_iprange)
        subnet_application_gateway_prefix = (
            props.subnet_application_gateway_iprange.apply(lambda r: str(r))
        )
        subnet_data_configuration_prefix = (
            props.subnet_data_configuration_iprange.apply(lambda r: str(r))
        )
        subnet_data_private_prefix = props.subnet_data_private_iprange.apply(
            lambda r: str(r)
        )
        subnet_guacamole_containers_prefix = (
            props.subnet_guacamole_containers_iprange.apply(lambda r: str(r))
        )
        subnet_guacamole_containers_support_prefix = (
            props.subnet_guacamole_containers_support_iprange.apply(lambda r: str(r))
        )
        subnet_user_services_containers_prefix = (
            props.subnet_user_services_containers_iprange.apply(lambda r: str(r))
        )
        subnet_user_services_containers_support_prefix = (
            props.subnet_user_services_containers_support_iprange.apply(
                lambda r: str(r)
            )
        )
        subnet_user_services_databases_prefix = (
            props.subnet_user_services_databases_iprange.apply(lambda r: str(r))
        )
        subnet_user_services_software_repositories_prefix = (
            props.subnet_user_services_software_repositories_iprange.apply(
                lambda r: str(r)
            )
        )
        subnet_workspaces_prefix = props.subnet_workspaces_iprange.apply(
            lambda r: str(r)
        )

        # Define NSGs
        nsg_application_gateway = network.NetworkSecurityGroup(
            f"{self._name}_nsg_application_gateway",
            network_security_group_name=f"{stack_name}-nsg-application-gateway",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound gateway management service traffic.",
                    destination_address_prefix="*",
                    destination_port_range="65200-65535",
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
                    destination_address_prefix=subnet_application_gateway_prefix,
                    destination_port_ranges=["80", "443"],
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
                    destination_address_prefix=subnet_application_gateway_prefix,
                    destination_port_ranges=["443"],
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
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to DNS servers.",
                    destination_address_prefix=dns_servers_prefix,
                    destination_port_ranges=["53"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_application_gateway_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to the Guacamole remote desktop gateway.",
                    destination_address_prefix=subnet_guacamole_containers_prefix,
                    destination_port_ranges=["80"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowGuacamoleContainersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_GUACAMOLE_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_application_gateway_prefix,
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
                # this NSG to fail validation. See: https://learn.microsoft.com/en-us/azure/application-gateway/configuration-infrastructure#network-security-groups
            ],
            opts=child_opts,
        )
        nsg_data_configuration = network.NetworkSecurityGroup(
            f"{self._name}_nsg_data_configuration",
            network_security_group_name=f"{stack_name}-nsg-data-configuration",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from Guacamole remote desktop gateway.",
                    destination_address_prefix=subnet_data_configuration_prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowGuacamoleContainersInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_GUACAMOLE_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_guacamole_containers_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from user services containers.",
                    destination_address_prefix=subnet_data_configuration_prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowUserServicesContainersInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_user_services_containers_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from user services software repositories.",
                    destination_address_prefix=subnet_data_configuration_prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowUserServicesSoftwareRepositoriesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_SOFTWARE_REPOSITORIES,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_user_services_software_repositories_prefix,
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
        )
        nsg_data_private = network.NetworkSecurityGroup(
            f"{self._name}_nsg_data_private",
            network_security_group_name=f"{stack_name}-nsg-data-private",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from SRE workspaces.",
                    destination_address_prefix=subnet_data_private_prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowWorkspacesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_workspaces_prefix,
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
        )
        nsg_guacamole_containers = network.NetworkSecurityGroup(
            f"{self._name}_nsg_guacamole_containers",
            network_security_group_name=f"{stack_name}-nsg-guacamole-containers",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from the Application Gateway.",
                    destination_address_prefix=subnet_guacamole_containers_prefix,
                    destination_port_ranges=["80"],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowApplicationGatewayInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_APPLICATION_GATEWAY,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_application_gateway_prefix,
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
                    destination_address_prefix=dns_servers_prefix,
                    destination_port_ranges=["53"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_guacamole_containers_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow LDAP client requests over TCP.",
                    destination_address_prefix=props.shm_subnet_identity_servers_prefix,
                    destination_port_ranges=["389", "636"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowLDAPClientTCPOutbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_LDAP_TCP,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_guacamole_containers_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to configuration data endpoints.",
                    destination_address_prefix=subnet_data_configuration_prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataConfigurationEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_CONFIGURATION,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_guacamole_containers_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to Guacamole support services.",
                    destination_address_prefix=subnet_guacamole_containers_support_prefix,
                    destination_port_ranges=["5432"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowGuacamoleContainersSupportOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_GUACAMOLE_CONTAINERS_SUPPORT,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_guacamole_containers_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to SRE workspaces.",
                    destination_address_prefix=subnet_workspaces_prefix,
                    destination_port_ranges=["22", "3389"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowWorkspacesOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_guacamole_containers_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound OAuth connections over the internet.",
                    destination_address_prefix="Internet",
                    destination_port_ranges=["80", "443"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowOAuthInternetOutbound",
                    priority=NetworkingPriorities.EXTERNAL_INTERNET,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_guacamole_containers_prefix,
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
        nsg_guacamole_containers_support = network.NetworkSecurityGroup(
            f"{self._name}_nsg_guacamole_containers_support",
            network_security_group_name=f"{stack_name}-nsg-guacamole-containers-support",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from Guacamole remote desktop gateway.",
                    destination_address_prefix=subnet_guacamole_containers_support_prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowGuacamoleContainersInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_GUACAMOLE_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_guacamole_containers_prefix,
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
        )
        nsg_user_services_containers = network.NetworkSecurityGroup(
            f"{self._name}_nsg_user_services_containers",
            network_security_group_name=f"{stack_name}-nsg-user-services-containers",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from SRE workspaces.",
                    destination_address_prefix=subnet_user_services_containers_prefix,
                    destination_port_ranges=["22", "80", "443"],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowWorkspacesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_workspaces_prefix,
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
                    destination_address_prefix=dns_servers_prefix,
                    destination_port_ranges=["53"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_user_services_containers_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow LDAP client requests over TCP.",
                    destination_address_prefix=props.shm_subnet_identity_servers_prefix,
                    destination_port_ranges=["389", "636"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowLDAPClientTCPOutbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_LDAP_TCP,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_user_services_containers_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to configuration data endpoints.",
                    destination_address_prefix=subnet_data_configuration_prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataConfigurationEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_CONFIGURATION,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_user_services_containers_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to container support services.",
                    destination_address_prefix=subnet_user_services_containers_support_prefix,
                    destination_port_ranges=["5432"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowUserServicesContainersSupportOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_CONTAINERS_SUPPORT,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_user_services_containers_prefix,
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
        nsg_user_services_containers_support = network.NetworkSecurityGroup(
            f"{self._name}_nsg_user_services_containers_support",
            network_security_group_name=f"{stack_name}-nsg-user-services-containers-support",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from user services containers.",
                    destination_address_prefix=subnet_user_services_containers_support_prefix,
                    destination_port_ranges=["5432"],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowUserServicesContainersInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_user_services_containers_prefix,
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
        )
        nsg_user_services_databases = network.NetworkSecurityGroup(
            f"{self._name}_nsg_user_services_databases",
            network_security_group_name=f"{stack_name}-nsg-user-services-databases",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from SRE workspaces.",
                    destination_address_prefix=subnet_user_services_databases_prefix,
                    destination_port_ranges=["1433", "5432"],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowWorkspacesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_workspaces_prefix,
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
                    destination_address_prefix=dns_servers_prefix,
                    destination_port_ranges=["53"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_user_services_databases_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to configuration data endpoints.",
                    destination_address_prefix=subnet_data_configuration_prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataConfigurationEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_CONFIGURATION,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_user_services_databases_prefix,
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
        nsg_user_services_software_repositories = network.NetworkSecurityGroup(
            f"{self._name}_nsg_user_services_software_repositories",
            network_security_group_name=f"{stack_name}-nsg-user-services-software-repositories",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from SRE workspaces.",
                    destination_address_prefix=subnet_user_services_software_repositories_prefix,
                    destination_port_ranges=["80", "443", "3128"],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowWorkspacesInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_WORKSPACES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_workspaces_prefix,
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
                    destination_address_prefix=dns_servers_prefix,
                    destination_port_ranges=["53"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_user_services_software_repositories_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to configuration data endpoints.",
                    destination_address_prefix=subnet_data_configuration_prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataConfigurationEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_CONFIGURATION,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_user_services_software_repositories_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to external repositories over the internet.",
                    destination_address_prefix="Internet",
                    destination_port_ranges=["80", "443"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowPackagesInternetOutbound",
                    priority=NetworkingPriorities.EXTERNAL_INTERNET,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_user_services_software_repositories_prefix,
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
        nsg_workspaces = network.NetworkSecurityGroup(
            f"{self._name}_nsg_workspaces",
            network_security_group_name=f"{stack_name}-nsg-workspaces",
            resource_group_name=resource_group.name,
            security_rules=[
                # Inbound
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow inbound connections from Guacamole remote desktop gateway.",
                    destination_address_prefix=subnet_workspaces_prefix,
                    destination_port_ranges=["22", "3389"],
                    direction=network.SecurityRuleDirection.INBOUND,
                    name="AllowGuacamoleContainersInbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_GUACAMOLE_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_guacamole_containers_prefix,
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
                    description=(
                        "Allow LDAP client requests over TCP. "
                        "See https://devopstales.github.io/linux/pfsense-ad-join/ for details."
                    ),
                    destination_address_prefix=props.shm_subnet_identity_servers_prefix,
                    destination_port_ranges=["389", "636"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowLDAPClientTCPOutbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_LDAP_TCP,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_workspaces_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow LDAP client requests over UDP.",
                    destination_address_prefix=props.shm_subnet_identity_servers_prefix,
                    destination_port_ranges=["389", "636"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowLDAPClientUDPOutbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_LDAP_UDP,
                    protocol=network.SecurityRuleProtocol.UDP,
                    source_address_prefix=subnet_workspaces_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to SHM monitoring tools.",
                    destination_address_prefix=str(props.shm_subnet_monitoring_prefix),
                    destination_port_ranges=["443"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowMonitoringToolsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_MONITORING_TOOLS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_workspaces_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to Linux update servers.",
                    destination_address_prefix=props.shm_subnet_update_servers_prefix,
                    destination_port_ranges=["8000"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowLinuxUpdatesOutbound",
                    priority=NetworkingPriorities.INTERNAL_SHM_UPDATE_SERVERS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_workspaces_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to DNS servers.",
                    destination_address_prefix=dns_servers_prefix,
                    destination_port_ranges=["53", "3000"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDNSServersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DNS_SERVERS,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_workspaces_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to private data endpoints.",
                    destination_address_prefix=subnet_data_private_prefix,
                    destination_port_range="*",
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowDataPrivateEndpointsOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_DATA_PRIVATE,
                    protocol=network.SecurityRuleProtocol.ASTERISK,
                    source_address_prefix=subnet_workspaces_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to user services containers.",
                    destination_address_prefix=subnet_user_services_containers_prefix,
                    destination_port_ranges=["22", "80", "443"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowUserServicesContainersOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_CONTAINERS,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_workspaces_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to user services databases.",
                    destination_address_prefix=subnet_user_services_databases_prefix,
                    destination_port_ranges=["1433", "5432"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowUserServicesDatabasesOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_DATABASES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_workspaces_prefix,
                    source_port_range="*",
                ),
                network.SecurityRuleArgs(
                    access=network.SecurityRuleAccess.ALLOW,
                    description="Allow outbound connections to user services software repositories.",
                    destination_address_prefix=subnet_user_services_software_repositories_prefix,
                    destination_port_ranges=["80", "443", "3128"],
                    direction=network.SecurityRuleDirection.OUTBOUND,
                    name="AllowUserServicesSoftwareRepositoriesOutbound",
                    priority=NetworkingPriorities.INTERNAL_SRE_USER_SERVICES_SOFTWARE_REPOSITORIES,
                    protocol=network.SecurityRuleProtocol.TCP,
                    source_address_prefix=subnet_workspaces_prefix,
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
                    source_address_prefix=subnet_workspaces_prefix,
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

        # Define the virtual network and its subnets
        subnet_application_gateway_name = "ApplicationGatewaySubnet"
        subnet_data_configuration_name = "DataConfigurationSubnet"
        subnet_data_private_name = "DataPrivateSubnet"
        subnet_guacamole_containers_name = "GuacamoleContainersSubnet"
        subnet_guacamole_containers_support_name = "GuacamoleContainersSupportSubnet"
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
                address_prefixes=[props.vnet_iprange.apply(lambda r: str(r))],
            ),
            dhcp_options=network.DhcpOptionsArgs(dns_servers=[props.dns_server_ip]),
            resource_group_name=resource_group.name,
            # Note that we define subnets inline to avoid creation order issues
            subnets=[
                # Application gateway subnet
                network.SubnetArgs(
                    address_prefix=subnet_application_gateway_prefix,
                    name=subnet_application_gateway_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_application_gateway.id
                    ),
                    route_table=None,  # the application gateway must not go via the firewall
                ),
                # Configuration data subnet
                network.SubnetArgs(
                    address_prefix=subnet_data_configuration_prefix,
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
                # Private data
                network.SubnetArgs(
                    address_prefix=subnet_data_private_prefix,
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
                # Guacamole containers
                network.SubnetArgs(
                    address_prefix=subnet_guacamole_containers_prefix,
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
                    address_prefix=subnet_guacamole_containers_support_prefix,
                    name=subnet_guacamole_containers_support_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_guacamole_containers_support.id
                    ),
                    private_endpoint_network_policies="Disabled",
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # User services containers
                network.SubnetArgs(
                    address_prefix=subnet_user_services_containers_prefix,
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
                    address_prefix=subnet_user_services_containers_support_prefix,
                    name=subnet_user_services_containers_support_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_user_services_containers_support.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # User services databases
                network.SubnetArgs(
                    address_prefix=subnet_user_services_databases_prefix,
                    name=subnet_user_services_databases_name,
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_user_services_databases.id
                    ),
                    route_table=network.RouteTableArgs(id=route_table.id),
                ),
                # User services software repositories
                network.SubnetArgs(
                    address_prefix=subnet_user_services_software_repositories_prefix,
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
                    address_prefix=subnet_workspaces_prefix,
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
        )

        # Peer the SRE virtual network to the SHM virtual network
        shm_virtual_network = Output.all(
            resource_group_name=props.shm_networking_resource_group_name,
            virtual_network_name=props.shm_virtual_network_name,
        ).apply(
            lambda kwargs: network.get_virtual_network(
                resource_group_name=kwargs["resource_group_name"],
                virtual_network_name=kwargs["virtual_network_name"],
            )
        )
        network.VirtualNetworkPeering(
            f"{self._name}_sre_to_shm_peering",
            remote_virtual_network=network.SubResourceArgs(id=shm_virtual_network.id),
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
            virtual_network_peering_name=Output.concat(
                "peer_sre_", props.sre_name, "_to_shm"
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=sre_virtual_network)
            ),
        )
        network.VirtualNetworkPeering(
            f"{self._name}_shm_to_sre_peering",
            allow_gateway_transit=True,
            remote_virtual_network=network.SubResourceArgs(id=sre_virtual_network.id),
            resource_group_name=props.shm_networking_resource_group_name,
            virtual_network_name=shm_virtual_network.name,
            virtual_network_peering_name=Output.concat(
                "peer_shm_to_sre_", props.sre_name
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=sre_virtual_network)
            ),
        )

        # Peer the SRE virtual network to the DNS virtual network
        network.VirtualNetworkPeering(
            f"{self._name}_sre_to_dns_peering",
            remote_virtual_network=network.SubResourceArgs(
                id=props.dns_virtual_network_id
            ),
            resource_group_name=resource_group.name,
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
            resource_group_name=props.dns_resource_group_name,
            virtual_network_name=props.dns_virtual_network_name,
            virtual_network_peering_name=Output.concat(
                "peer_dns_to_sre_", props.sre_name
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=sre_virtual_network)
            ),
        )

        # Define SRE DNS zone
        shm_dns_zone = Output.all(
            resource_group_name=props.shm_networking_resource_group_name,
            zone_name=props.shm_zone_name,
        ).apply(
            lambda kwargs: network.get_zone(
                resource_group_name=kwargs["resource_group_name"],
                zone_name=kwargs["zone_name"],
            )
        )
        sre_subdomain = Output.from_input(props.sre_name).apply(
            lambda name: alphanumeric(name).lower()
        )
        sre_fqdn = Output.concat(sre_subdomain, ".", props.shm_fqdn)
        sre_dns_zone = network.Zone(
            f"{self._name}_dns_zone",
            location="Global",
            resource_group_name=resource_group.name,
            zone_name=sre_fqdn,
            zone_type=network.ZoneType.PUBLIC,
            opts=child_opts,
        )
        shm_ns_record = network.RecordSet(
            f"{self._name}_ns_record",
            ns_records=sre_dns_zone.name_servers.apply(
                lambda servers: [network.NsRecordArgs(nsdname=ns) for ns in servers]
            ),
            record_type="NS",
            relative_record_set_name=sre_subdomain,
            resource_group_name=props.shm_networking_resource_group_name,
            ttl=3600,
            zone_name=shm_dns_zone.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=sre_dns_zone)
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
            resource_group_name=resource_group.name,
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
            resource_group_name=props.dns_resource_group_name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=sre_dns_zone)
            ),
        )
        network.VirtualNetworkLink(
            f"{self._name}_private_zone_internal_vnet_link",
            location="Global",
            private_zone_name=sre_private_dns_zone.name,
            registration_enabled=False,
            resource_group_name=props.dns_resource_group_name,
            virtual_network=network.SubResourceArgs(id=props.dns_virtual_network_id),
            virtual_network_link_name=Output.concat(
                "link-to-", props.dns_virtual_network_name
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=sre_private_dns_zone)
            ),
        )

        # Link virtual network to SHM private DNS zones
        # Note that although the DNS virtual network is already linked to these, Azure
        # Container Instances do not have an IP address during deployment and so must
        # use default Azure DNS when setting up file mounts. This means that we need to
        # be able to resolve the "Storage Account" private DNS zones.
        for private_link_domain in ordered_private_dns_zones("Storage account"):
            network.VirtualNetworkLink(
                f"{self._name}_private_zone_{private_link_domain}_vnet_link",
                location="Global",
                private_zone_name=f"privatelink.{private_link_domain}",
                registration_enabled=False,
                resource_group_name=props.shm_networking_resource_group_name,
                virtual_network=network.SubResourceArgs(id=sre_virtual_network.id),
                virtual_network_link_name=Output.concat(
                    "link-to-", sre_virtual_network.name
                ),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=sre_virtual_network)
                ),
            )

        # Register outputs
        self.resource_group = resource_group
        self.shm_ns_record = shm_ns_record
        self.sre_fqdn = sre_dns_zone.name
        self.sre_private_dns_zone_id = sre_private_dns_zone.id
        self.sre_private_dns_zone = sre_private_dns_zone
        self.subnet_application_gateway = network.get_subnet_output(
            subnet_name=subnet_application_gateway_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_data_configuration = network.get_subnet_output(
            subnet_name=subnet_data_configuration_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_guacamole_containers = network.get_subnet_output(
            subnet_name=subnet_guacamole_containers_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_guacamole_containers_support = network.get_subnet_output(
            subnet_name=subnet_guacamole_containers_support_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_data_private = network.get_subnet_output(
            subnet_name=subnet_data_private_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_user_services_containers = network.get_subnet_output(
            subnet_name=subnet_user_services_containers_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_user_services_containers_support = network.get_subnet_output(
            subnet_name=subnet_user_services_containers_support_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_user_services_databases = network.get_subnet_output(
            subnet_name=subnet_user_services_databases_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_user_services_software_repositories = network.get_subnet_output(
            subnet_name=subnet_user_services_software_repositories_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.subnet_workspaces = network.get_subnet_output(
            subnet_name=subnet_workspaces_name,
            resource_group_name=resource_group.name,
            virtual_network_name=sre_virtual_network.name,
        )
        self.virtual_network = sre_virtual_network
