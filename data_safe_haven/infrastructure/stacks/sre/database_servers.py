from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, sql

from data_safe_haven.infrastructure.common import get_ip_addresses_from_private_endpoint
from data_safe_haven.infrastructure.components import (
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
    ) -> None:
        super().__init__("dsh:sre:DatabaseServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

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
            )
            # Add the Microsoft SQL server to the SRE private DNS zone
            private_dns_record_set = network.PrivateRecordSet(
                f"{self._name}_db_server_mssql_private_record_set",
                a_records=[
                    network.ARecordArgs(
                        ipv4_address=get_ip_addresses_from_private_endpoint(
                            db_server_mssql_private_endpoint
                        ).apply(lambda ips: ips[0]),
                    )
                ],
                private_zone_name=Output.concat("privatelink.", props.sre_fqdn),
                record_type="A",
                relative_record_set_name="mssql",
                resource_group_name=props.dns_resource_group_name,
                ttl=3600,
                opts=ResourceOptions.merge(
                    child_opts,
                    ResourceOptions(parent=db_server_mssql_private_endpoint),
                ),
            )
            # Redirect the Microsoft SQL server public DNS record to private DNS
            network.RecordSet(
                f"{self._name}_db_server_mssql_public_record_set",
                cname_record=network.CnameRecordArgs(
                    cname=Output.concat("mssql.privatelink.", props.sre_fqdn)
                ),
                record_type="CNAME",
                relative_record_set_name="mssql",
                resource_group_name=props.networking_resource_group_name,
                ttl=3600,
                zone_name=props.sre_fqdn,
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=private_dns_record_set)
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
            )
            # Add the PostgreSQL server to the SRE private DNS zone
            private_dns_record_set = network.PrivateRecordSet(
                f"{self._name}_db_server_postgresql_private_record_set",
                a_records=[
                    network.ARecordArgs(
                        ipv4_address=db_server_postgresql.private_ip_address,
                    )
                ],
                private_zone_name=Output.concat("privatelink.", props.sre_fqdn),
                record_type="A",
                relative_record_set_name="postgresql",
                resource_group_name=props.dns_resource_group_name,
                ttl=3600,
                opts=ResourceOptions.merge(
                    child_opts,
                    ResourceOptions(parent=db_server_postgresql.private_endpoint),
                ),
            )
            # Redirect the PostgreSQL server public DNS record to private DNS
            network.RecordSet(
                f"{self._name}_db_server_postgresql_public_record_set",
                cname_record=network.CnameRecordArgs(
                    cname=Output.concat("postgresql.privatelink.", props.sre_fqdn)
                ),
                record_type="CNAME",
                relative_record_set_name="postgresql",
                resource_group_name=props.networking_resource_group_name,
                ttl=3600,
                zone_name=props.sre_fqdn,
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=private_dns_record_set)
                ),
            )
