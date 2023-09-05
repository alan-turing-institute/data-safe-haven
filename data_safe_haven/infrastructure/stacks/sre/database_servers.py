from collections.abc import Mapping

from pulumi import ComponentResource, Input, ResourceOptions
from pulumi_azure_native import network, sql

from data_safe_haven.infrastructure.common import get_ip_addresses_from_private_endpoint
from data_safe_haven.infrastructure.components import (
    LocalDnsRecordComponent,
    LocalDnsRecordProps,
    PostgresqlDatabaseComponent,
    PostgresqlDatabaseProps,
)
from data_safe_haven.utility import DatabaseSystem


class SREDatabaseServerProps:
    """Properties for SREDatabaseServerComponent"""

    def __init__(
        self,
        database_password: Input[str],
        database_system: DatabaseSystem,  # this must *not* be passed as an Input[T]
        dns_resource_group_name: Input[str],
        location: Input[str],
        networking_resource_group_name: Input[str],
        sre_fqdn: Input[str],
        subnet_id: Input[str],
        user_services_resource_group_name: Input[str],
        database_username: Input[str] | None = None,
    ) -> None:
        self.database_password = database_password
        self.database_system = database_system
        self.database_username = (
            database_username if database_username else "databaseadmin"
        )
        self.dns_resource_group_name = dns_resource_group_name
        self.location = location
        self.networking_resource_group_name = networking_resource_group_name
        self.sre_fqdn = sre_fqdn
        self.subnet_id = subnet_id
        self.user_services_resource_group_name = user_services_resource_group_name


class SREDatabaseServerComponent(ComponentResource):
    """Deploy database server with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREDatabaseServerProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:DatabaseServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        if props.database_system == DatabaseSystem.MICROSOFT_SQL_SERVER:
            # Define a Microsoft SQL server
            db_server_mssql_name = f"{stack_name}-db-server-mssql"
            db_server_mssql = sql.Server(
                f"{self._name}_db_server_mssql",
                administrator_login=props.database_username,
                administrator_login_password=props.database_password,
                location=props.location,
                minimal_tls_version=None,
                public_network_access=sql.ServerPublicNetworkAccess.DISABLED,
                resource_group_name=props.user_services_resource_group_name,
                server_name=db_server_mssql_name,
                version="12.0",
                opts=child_opts,
                tags=child_tags,
            )
            # Add a default database
            sql.Database(
                f"{self._name}_db_server_mssql_mssql",
                database_name="mssql",
                location=props.location,
                resource_group_name=props.user_services_resource_group_name,
                server_name=db_server_mssql_name,
                sku=sql.SkuArgs(
                    capacity=1,
                    family="Gen5",
                    name="GP_S_Gen5",
                ),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=db_server_mssql)
                ),
                tags=child_tags,
            )
            # Deploy a private endpoint for the Microsoft SQL server
            db_server_mssql_private_endpoint = network.PrivateEndpoint(
                f"{self._name}_db_server_mssql_private_endpoint",
                private_endpoint_name=f"{stack_name}-endpoint-db-server-mssql",
                private_link_service_connections=[
                    network.PrivateLinkServiceConnectionArgs(
                        group_ids=["sqlServer"],
                        name=f"{stack_name}-privatelink-db-server-mssql",
                        private_link_service_connection_state=network.PrivateLinkServiceConnectionStateArgs(
                            actions_required="None",
                            description="Auto-approved",
                            status="Approved",
                        ),
                        private_link_service_id=db_server_mssql.id,
                    )
                ],
                resource_group_name=props.user_services_resource_group_name,
                subnet=network.SubnetArgs(id=props.subnet_id),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=db_server_mssql)
                ),
                tags=child_tags,
            )
            # Register the database in the SRE DNS zone
            LocalDnsRecordComponent(
                f"{self._name}_mssql_dns_record_set",
                LocalDnsRecordProps(
                    base_fqdn=props.sre_fqdn,
                    public_dns_resource_group_name=props.networking_resource_group_name,
                    private_dns_resource_group_name=props.dns_resource_group_name,
                    private_ip_address=get_ip_addresses_from_private_endpoint(
                        db_server_mssql_private_endpoint
                    ).apply(lambda ips: ips[0]),
                    record_name="mssql",
                ),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=db_server_mssql)
                ),
            )

        if props.database_system == DatabaseSystem.POSTGRESQL:
            # Define a PostgreSQL server and default database
            db_server_postgresql = PostgresqlDatabaseComponent(
                f"{self._name}_db_postgresql",
                PostgresqlDatabaseProps(
                    database_names=[],
                    database_password=props.database_password,
                    database_resource_group_name=props.user_services_resource_group_name,
                    database_server_name=f"{stack_name}-db-server-postgresql",
                    database_subnet_id=props.subnet_id,
                    database_username=props.database_username,
                    location=props.location,
                ),
                opts=child_opts,
                tags=child_tags,
            )
            # Register the database in the SRE DNS zone
            LocalDnsRecordComponent(
                f"{self._name}_postgresql_dns_record_set",
                LocalDnsRecordProps(
                    base_fqdn=props.sre_fqdn,
                    public_dns_resource_group_name=props.networking_resource_group_name,
                    private_dns_resource_group_name=props.dns_resource_group_name,
                    private_ip_address=db_server_postgresql.private_ip_address,
                    record_name="postgresql",
                ),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=db_server_postgresql)
                ),
            )
