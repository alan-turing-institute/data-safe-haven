# Standard library imports
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

# Local imports
from data_safe_haven.pulumi.common.transformations import (
    get_available_ips_from_subnet,
    get_id_from_subnet,
)
from .sre_gitea_server import SREGiteaServerComponent, SREGiteaServerProps


class SREUserServicesProps:
    """Properties for SREUserServicesComponent"""

    def __init__(
        self,
        ldap_root_dn: Input[str],
        ldap_search_password: Input[str],
        ldap_server_ip: Input[str],
        ldap_security_group_name: Input[str],
        location: Input[str],
        networking_resource_group_name: Input[str],
        sre_fqdn: Input[str],
        sre_private_dns_zone_id: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
        subnet: Input[network.GetSubnetResult],
        virtual_network: Input[network.VirtualNetwork],
        virtual_network_resource_group_name: Input[str],
    ):
        self.ldap_root_dn = ldap_root_dn
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.ldap_security_group_name = ldap_security_group_name
        self.location = location
        self.networking_resource_group_name = networking_resource_group_name
        self.sre_fqdn = sre_fqdn
        self.sre_private_dns_zone_id = sre_private_dns_zone_id
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group_name = storage_account_resource_group_name
        self.subnet_id = Output.from_input(subnet).apply(get_id_from_subnet)
        self.subnet_ip_addresses = Output.from_input(subnet).apply(
            get_available_ips_from_subnet
        )
        self.virtual_network = virtual_network
        self.virtual_network_resource_group_name = virtual_network_resource_group_name


class SREUserServicesComponent(ComponentResource):
    """Deploy secure research desktops with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SREUserServicesProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:sre:SREUserServicesComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-user-services",
            opts=child_opts,
        )

        # Define a network profile
        container_network_profile = network.NetworkProfile(
            f"{self._name}_container_network_profile",
            container_network_interface_configurations=[
                network.ContainerNetworkInterfaceConfigurationArgs(
                    ip_configurations=[
                        network.IPConfigurationProfileArgs(
                            name="ipconfiguserservices",
                            subnet=network.SubnetArgs(
                                id=props.subnet_id,
                            ),
                        )
                    ],
                    name="networkinterfaceconfiguserservices",
                )
            ],
            network_profile_name=f"{stack_name}-np-user-services",
            resource_group_name=props.virtual_network_resource_group_name,
            opts=ResourceOptions.merge(
                ResourceOptions(depends_on=[props.virtual_network]), child_opts
            ),
        )

        gitea_server = SREGiteaServerComponent(
            "sre_gitea_server",
            stack_name,
            sre_name,
            SREGiteaServerProps(
                ldap_root_dn=props.ldap_root_dn,
                ldap_search_password=props.ldap_search_password,
                ldap_server_ip=props.ldap_server_ip,
                ldap_security_group_name=props.ldap_security_group_name,
                location=props.location,
                networking_resource_group_name=props.networking_resource_group_name,
                network_profile_id=container_network_profile.id,
                sre_fqdn=props.sre_fqdn,
                sre_private_dns_zone_id=props.sre_private_dns_zone_id,
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
                storage_account_resource_group_name=props.storage_account_resource_group_name,
                subnet_id=props.subnet_id,
                subnet_ip_address=props.subnet_ip_addresses[0],
                user_services_resource_group_name=resource_group.name,
                virtual_network=props.virtual_network,
                virtual_network_resource_group_name=props.virtual_network_resource_group_name,
            ),
            opts=child_opts,
        )
