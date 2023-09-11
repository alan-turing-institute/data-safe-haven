from collections.abc import Mapping

from pulumi import ComponentResource, Input, ResourceOptions

from data_safe_haven.infrastructure.components import (
    LocalDnsRecordComponent,
    LocalDnsRecordProps,
    MicrosoftSQLDatabaseComponent,
    MicrosoftSQLDatabaseProps,
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
            # Define a Microsoft SQL server and default database
            db_server_mssql = MicrosoftSQLDatabaseComponent(
                f"{self._name}_db_mssql",
                MicrosoftSQLDatabaseProps(
                    database_names=[],
                    database_password=props.database_password,
                    database_resource_group_name=props.user_services_resource_group_name,
                    database_server_name=f"{stack_name}-db-server-mssql",
                    database_subnet_id=props.subnet_id,
                    database_username=props.database_username,
                    location=props.location,
                ),
                opts=child_opts,
                tags=child_tags,
            )
            # Register the database in the SRE DNS zone
            LocalDnsRecordComponent(
                f"{self._name}_mssql_dns_record_set",
                LocalDnsRecordProps(
                    base_fqdn=props.sre_fqdn,
                    public_dns_resource_group_name=props.networking_resource_group_name,
                    private_dns_resource_group_name=props.dns_resource_group_name,
                    private_ip_address=db_server_mssql.private_ip_address,
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
