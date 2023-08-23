from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

from data_safe_haven.pulumi.common import get_id_from_subnet
from data_safe_haven.utility import DatabaseSystem, SoftwarePackageCategory

from .sre_database_server import SREDatabaseServerComponent, SREDatabaseServerProps
from .sre_gitea_server import SREGiteaServerComponent, SREGiteaServerProps
from .sre_hedgedoc_server import SREHedgeDocServerComponent, SREHedgeDocServerProps
from .sre_software_repositories import (
    SRESoftwareRepositoriesComponent,
    SRESoftwareRepositoriesProps,
)


class SREUserServicesProps:
    """Properties for SREUserServicesComponent"""

    def __init__(
        self,
        database_service_admin_password: Input[str],
        databases: list[DatabaseSystem],  # this must *not* be passed as an Input[T]
        dns_resource_group_name: Input[str],
        dns_server_ip: Input[str],
        domain_netbios_name: Input[str],
        gitea_database_password: Input[str],
        hedgedoc_database_password: Input[str],
        ldap_bind_dn: Input[str],
        ldap_root_dn: Input[str],
        ldap_search_password: Input[str],
        ldap_server_ip: Input[str],
        ldap_user_search_base: Input[str],
        ldap_user_security_group_name: Input[str],
        location: Input[str],
        networking_resource_group_name: Input[str],
        nexus_admin_password: Input[str],
        software_packages: SoftwarePackageCategory,
        sre_fqdn: Input[str],
        sre_private_dns_zone_id: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
        subnet_containers: Input[network.GetSubnetResult],
        subnet_containers_support: Input[network.GetSubnetResult],
        subnet_databases: Input[network.GetSubnetResult],
        subnet_software_repositories: Input[network.GetSubnetResult],
        virtual_network: Input[network.VirtualNetwork],
        virtual_network_resource_group_name: Input[str],
    ) -> None:
        self.database_service_admin_password = database_service_admin_password
        self.databases = databases
        self.dns_resource_group_name = dns_resource_group_name
        self.dns_server_ip = dns_server_ip
        self.domain_netbios_name = domain_netbios_name
        self.gitea_database_password = gitea_database_password
        self.hedgedoc_database_password = hedgedoc_database_password
        self.ldap_bind_dn = ldap_bind_dn
        self.ldap_root_dn = ldap_root_dn
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.ldap_user_search_base = ldap_user_search_base
        self.ldap_user_security_group_name = ldap_user_security_group_name
        self.location = location
        self.networking_resource_group_name = networking_resource_group_name
        self.nexus_admin_password = Output.secret(nexus_admin_password)
        self.software_packages = software_packages
        self.sre_fqdn = sre_fqdn
        self.sre_private_dns_zone_id = sre_private_dns_zone_id
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group_name = storage_account_resource_group_name
        self.subnet_containers_id = Output.from_input(subnet_containers).apply(
            get_id_from_subnet
        )
        self.subnet_containers_support_id = Output.from_input(
            subnet_containers_support
        ).apply(get_id_from_subnet)
        self.subnet_databases_id = Output.from_input(subnet_databases).apply(
            get_id_from_subnet
        )
        self.subnet_software_repositories_id = Output.from_input(
            subnet_software_repositories
        ).apply(get_id_from_subnet)
        self.virtual_network = virtual_network
        self.virtual_network_resource_group_name = virtual_network_resource_group_name


class SREUserServicesComponent(ComponentResource):
    """Deploy user services with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREUserServicesProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:UserServicesComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

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
                                id=props.subnet_containers_id,
                            ),
                        )
                    ],
                    name="networkinterfaceconfiguserservices",
                )
            ],
            network_profile_name=f"{stack_name}-np-user-services",
            resource_group_name=props.virtual_network_resource_group_name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    depends_on=[props.virtual_network],
                    ignore_changes=[
                        "container_network_interface_configurations"
                    ],  # allow container groups to be registered to this interface
                ),
            ),
        )

        # Deploy the Gitea server
        SREGiteaServerComponent(
            "sre_gitea_server",
            stack_name,
            SREGiteaServerProps(
                database_subnet_id=props.subnet_containers_support_id,
                database_password=props.gitea_database_password,
                dns_resource_group_name=props.dns_resource_group_name,
                dns_server_ip=props.dns_server_ip,
                ldap_bind_dn=props.ldap_bind_dn,
                ldap_root_dn=props.ldap_root_dn,
                ldap_search_password=props.ldap_search_password,
                ldap_server_ip=props.ldap_server_ip,
                ldap_user_security_group_name=props.ldap_user_security_group_name,
                ldap_user_search_base=props.ldap_user_search_base,
                location=props.location,
                networking_resource_group_name=props.networking_resource_group_name,
                network_profile_id=container_network_profile.id,
                sre_fqdn=props.sre_fqdn,
                sre_private_dns_zone_id=props.sre_private_dns_zone_id,
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
                storage_account_resource_group_name=props.storage_account_resource_group_name,
                user_services_resource_group_name=resource_group.name,
                virtual_network=props.virtual_network,
                virtual_network_resource_group_name=props.virtual_network_resource_group_name,
            ),
            opts=child_opts,
        )

        # Deploy the HedgeDoc server
        SREHedgeDocServerComponent(
            "sre_hedgedoc_server",
            stack_name,
            SREHedgeDocServerProps(
                database_subnet_id=props.subnet_containers_support_id,
                database_password=props.hedgedoc_database_password,
                dns_resource_group_name=props.dns_resource_group_name,
                dns_server_ip=props.dns_server_ip,
                domain_netbios_name=props.domain_netbios_name,
                ldap_bind_dn=props.ldap_bind_dn,
                ldap_root_dn=props.ldap_root_dn,
                ldap_search_password=props.ldap_search_password,
                ldap_server_ip=props.ldap_server_ip,
                ldap_user_security_group_name=props.ldap_user_security_group_name,
                ldap_user_search_base=props.ldap_user_search_base,
                location=props.location,
                networking_resource_group_name=props.networking_resource_group_name,
                network_profile_id=container_network_profile.id,
                sre_fqdn=props.sre_fqdn,
                sre_private_dns_zone_id=props.sre_private_dns_zone_id,
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
                storage_account_resource_group_name=props.storage_account_resource_group_name,
                user_services_resource_group_name=resource_group.name,
                virtual_network=props.virtual_network,
                virtual_network_resource_group_name=props.virtual_network_resource_group_name,
            ),
            opts=child_opts,
        )

        # Deploy software repository servers
        SRESoftwareRepositoriesComponent(
            "sre_software_repositories",
            stack_name,
            SRESoftwareRepositoriesProps(
                dns_resource_group_name=props.dns_resource_group_name,
                dns_server_ip=props.dns_server_ip,
                location=props.location,
                networking_resource_group_name=props.networking_resource_group_name,
                nexus_admin_password=props.nexus_admin_password,
                sre_fqdn=props.sre_fqdn,
                software_packages=props.software_packages,
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
                storage_account_resource_group_name=props.storage_account_resource_group_name,
                subnet_id=props.subnet_software_repositories_id,
                user_services_resource_group_name=resource_group.name,
                virtual_network=props.virtual_network,
                virtual_network_resource_group_name=props.virtual_network_resource_group_name,
            ),
            opts=child_opts,
        )

        # Deploy whichever database systems are selected
        for database in props.databases:
            SREDatabaseServerComponent(
                f"sre_{database.value}_database_server",
                stack_name,
                SREDatabaseServerProps(
                    database_password=props.database_service_admin_password,
                    database_system=database,
                    dns_resource_group_name=props.dns_resource_group_name,
                    location=props.location,
                    networking_resource_group_name=props.networking_resource_group_name,
                    sre_fqdn=props.sre_fqdn,
                    subnet_id=props.subnet_databases_id,
                    user_services_resource_group_name=resource_group.name,
                ),
                opts=child_opts,
            )
