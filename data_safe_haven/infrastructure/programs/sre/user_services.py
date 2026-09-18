from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network

from data_safe_haven.config.config_sections import ConfigSubsectionGiteaMirror
from data_safe_haven.infrastructure.common import (
    DockerHubCredentials,
    get_id_from_subnet,
)
from data_safe_haven.infrastructure.components import (
    OperationalInsightsWorkspace,
    PostgresqlDatabaseComponent,
    PostgresqlDatabaseProps,
)
from data_safe_haven.types import DatabaseSystem, SoftwarePackageCategory

from .database_servers import SREDatabaseServerComponent, SREDatabaseServerProps
from .gitea_mirror_manager import (
    SREGiteaMirrorManagerComponent,
    SREGiteaMirrorManagerProps,
)
from .gitea_server import SREGiteaServerComponent, SREGiteaServerProps
from .hedgedoc_server import SREHedgeDocServerComponent, SREHedgeDocServerProps
from .software_repositories import (
    SRESoftwareRepositoriesComponent,
    SRESoftwareRepositoriesProps,
)


class SREUserServicesProps:
    """Properties for SREUserServicesComponent"""

    def __init__(
        self,
        database_service_admin_password: Input[str],
        databases: list[DatabaseSystem],  # this must *not* be passed as an Input[T]
        db_server_shared_password: Input[str],
        dns_server_ip: Input[str],
        dockerhub_credentials: DockerHubCredentials,
        ldap_server_hostname: Input[str],
        ldap_server_port: Input[int],
        ldap_username_attribute: Input[str],
        ldap_user_filter: Input[str],
        ldap_user_search_base: Input[str],
        location: Input[str],
        log_analytics_workspace: Input[OperationalInsightsWorkspace],
        nexus_admin_password: Input[str],
        resource_group_name: Input[str],
        software_packages: SoftwarePackageCategory,
        sre_fqdn: Input[str],
        nexus_persistent_quota_gb: Input[int],
        repository_data: ConfigSubsectionGiteaMirror,
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        software_repositories_database_password: Input[str],
        subnet_containers: Input[network.GetSubnetResult],
        subnet_containers_support: Input[network.GetSubnetResult],
        subnet_gitea_mirrors: Input[network.GetSubnetResult],
        subnet_databases: Input[network.GetSubnetResult],
        subnet_software_repositories: Input[network.GetSubnetResult] | None,
        subnet_software_repositories_support: Input[network.GetSubnetResult] | None,
        db_server_shared_username: Input[str] | None = None,
    ) -> None:
        self.database_service_admin_password = database_service_admin_password
        self.databases = databases
        self.db_server_shared_password = db_server_shared_password
        self.dns_server_ip = dns_server_ip
        self.dockerhub_credentials = dockerhub_credentials
        self.ldap_server_hostname = ldap_server_hostname
        self.ldap_server_port = ldap_server_port
        self.ldap_username_attribute = ldap_username_attribute
        self.ldap_user_filter = ldap_user_filter
        self.ldap_user_search_base = ldap_user_search_base
        self.location = location
        self.log_analytics_workspace = log_analytics_workspace
        self.nexus_admin_password = Output.secret(nexus_admin_password)
        self.repository_data = repository_data
        self.resource_group_name = resource_group_name
        self.nexus_persistent_quota_gb = nexus_persistent_quota_gb
        self.software_packages = software_packages
        self.software_repositories_database_password = Output.secret(
            software_repositories_database_password
        )
        self.sre_fqdn = sre_fqdn
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.subnet_containers_id = Output.from_input(subnet_containers).apply(
            get_id_from_subnet
        )
        self.subnet_containers_support_id = Output.from_input(
            subnet_containers_support
        ).apply(get_id_from_subnet)
        self.subnet_databases_id = Output.from_input(subnet_databases).apply(
            get_id_from_subnet
        )
        self.db_server_shared_username = (
            db_server_shared_username if db_server_shared_username else "postgresadmin"
        )

        self.subnet_gitea_mirrors_id: Output[str] | None = None
        if subnet_gitea_mirrors is not None:
            self.subnet_gitea_mirrors_id = Output.from_input(
                subnet_gitea_mirrors
            ).apply(get_id_from_subnet)

        self.subnet_software_repositories_id: Output[str] | None = None

        if subnet_software_repositories and subnet_software_repositories_support:
            self.subnet_software_repositories_id = Output.from_input(
                subnet_software_repositories
            ).apply(get_id_from_subnet)

            self.subnet_software_repositories_support = (
                subnet_software_repositories_support
            )


class SREUserServicesComponent(ComponentResource):
    """Deploy user services with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREUserServicesProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:UserServicesComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "user services"} | (tags if tags else {})

        # Deploy the shared PostgreSQL database
        self.db_server_shared = PostgresqlDatabaseComponent(
            f"{self._name}_db_server_shared",
            PostgresqlDatabaseProps(
                database_names=[],
                database_password=props.db_server_shared_password,
                database_resource_group_name=props.resource_group_name,
                database_server_name=f"{stack_name}-db-server-shared",
                database_subnet_id=props.subnet_containers_support_id,
                database_username=props.db_server_shared_username,
                disable_secure_transport=False,
                location=props.location,
            ),
            opts=child_opts,
            tags=child_tags,
        )

        # Deploy the Gitea server
        self.gitea_server = SREGiteaServerComponent(
            "sre_gitea_server",
            stack_name,
            SREGiteaServerProps(
                containers_subnet_id=props.subnet_containers_id,
                db_server_shared=self.db_server_shared,
                db_server_shared_password=props.db_server_shared_password,
                dns_server_ip=props.dns_server_ip,
                dockerhub_credentials=props.dockerhub_credentials,
                ldap_server_hostname=props.ldap_server_hostname,
                ldap_server_port=props.ldap_server_port,
                ldap_username_attribute=props.ldap_username_attribute,
                ldap_user_filter=props.ldap_user_filter,
                ldap_user_search_base=props.ldap_user_search_base,
                location=props.location,
                log_analytics_workspace=props.log_analytics_workspace,
                resource_group_name=props.resource_group_name,
                sre_fqdn=props.sre_fqdn,
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=child_opts,
            tags=child_tags,
        )

        # Deploy the Gitea Mirror
        if props.subnet_gitea_mirrors_id is not None:
            self.mirror_monitor = SREGiteaMirrorManagerComponent(
                "gitea_mirror_monitor",
                stack_name,
                SREGiteaMirrorManagerProps(
                    db_server_shared=self.db_server_shared,
                    db_server_shared_password=props.db_server_shared_password,
                    dns_server_ip=props.dns_server_ip,
                    dockerhub_credentials=props.dockerhub_credentials,
                    gitea_workspace_dns_record=self.gitea_server.dns_record_name,
                    location=props.location,
                    log_analytics_workspace=props.log_analytics_workspace,
                    mirror_manager_subnet_id=props.subnet_gitea_mirrors_id,
                    repository_data=props.repository_data,
                    resource_group_name=props.resource_group_name,
                    sre_fqdn=props.sre_fqdn,
                    storage_account_key=props.storage_account_key,
                    storage_account_name=props.storage_account_name,
                    workspace_username=self.gitea_server.workspace_username,
                    workspace_password=self.gitea_server.workspace_password,
                ),
                opts=child_opts,
                tags=child_tags,
            )

        # Deploy the HedgeDoc server
        self.hedgedoc_server = SREHedgeDocServerComponent(
            "sre_hedgedoc_server",
            stack_name,
            SREHedgeDocServerProps(
                containers_subnet_id=props.subnet_containers_id,
                db_server_shared=self.db_server_shared,
                db_server_shared_password=props.db_server_shared_password,
                dns_server_ip=props.dns_server_ip,
                dockerhub_credentials=props.dockerhub_credentials,
                ldap_server_hostname=props.ldap_server_hostname,
                ldap_server_port=props.ldap_server_port,
                ldap_username_attribute=props.ldap_username_attribute,
                ldap_user_filter=props.ldap_user_filter,
                ldap_user_search_base=props.ldap_user_search_base,
                location=props.location,
                log_analytics_workspace=props.log_analytics_workspace,
                resource_group_name=props.resource_group_name,
                sre_fqdn=props.sre_fqdn,
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=child_opts,
            tags=child_tags,
        )

        # Deploy software repository servers
        if (
            props.subnet_software_repositories_id
            and props.subnet_software_repositories_support
        ):
            self.software_repositories = SRESoftwareRepositoriesComponent(
                "sre_software_repositories",
                stack_name,
                SRESoftwareRepositoriesProps(
                    database_password=props.software_repositories_database_password,
                    dns_server_ip=props.dns_server_ip,
                    dockerhub_credentials=props.dockerhub_credentials,
                    location=props.location,
                    log_analytics_workspace=props.log_analytics_workspace,
                    nexus_admin_password=props.nexus_admin_password,
                    resource_group_name=props.resource_group_name,
                    sre_fqdn=props.sre_fqdn,
                    software_packages=props.software_packages,
                    nexus_persistent_quota_gb=props.nexus_persistent_quota_gb,
                    storage_account_key=props.storage_account_key,
                    storage_account_name=props.storage_account_name,
                    subnet_software_repositories_id=props.subnet_software_repositories_id,
                    subnet_software_repositories_support=props.subnet_software_repositories_support,
                ),
                opts=child_opts,
                tags=child_tags,
            )

        # Deploy whichever database systems are selected
        for database in props.databases:
            SREDatabaseServerComponent(
                f"sre_{database.value}_database_server",
                stack_name,
                SREDatabaseServerProps(
                    database_password=props.database_service_admin_password,
                    database_system=database,
                    location=props.location,
                    resource_group_name=props.resource_group_name,
                    sre_fqdn=props.sre_fqdn,
                    subnet_id=props.subnet_databases_id,
                ),
                opts=child_opts,
                tags=child_tags,
            )
