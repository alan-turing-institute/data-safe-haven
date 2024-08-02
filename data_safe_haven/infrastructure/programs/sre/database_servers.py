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
from data_safe_haven.types import DatabaseSystem


class SREDatabaseServerProps:
    """Properties for SREDatabaseServerComponent"""

    def __init__(
        self,
        database_password: Input[str],
        database_system: DatabaseSystem,  # this must *not* be passed as an Input[T]
        location: Input[str],
        resource_group_name: Input[str],
        sre_fqdn: Input[str],
        subnet_id: Input[str],
    ) -> None:
        self.database_password = database_password
        self.database_system = database_system
        self.database_username = "databaseadmin"
        self.location = location
        self.resource_group_name = resource_group_name
        self.sre_fqdn = sre_fqdn
        self.subnet_id = subnet_id


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
        child_tags = {"component": "database server"} | (tags if tags else {})

        if props.database_system == DatabaseSystem.MICROSOFT_SQL_SERVER:
            # Define a Microsoft SQL server and default database
            db_server_mssql = MicrosoftSQLDatabaseComponent(
                f"{self._name}_db_mssql",
                MicrosoftSQLDatabaseProps(
                    database_names=[],
                    database_password=props.database_password,
                    database_resource_group_name=props.resource_group_name,
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
                    private_ip_address=db_server_mssql.private_ip_address,
                    record_name="mssql",
                    resource_group_name=props.resource_group_name,
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
                    database_resource_group_name=props.resource_group_name,
                    database_server_name=f"{stack_name}-db-server-postgresql",
                    database_subnet_id=props.subnet_id,
                    database_username=props.database_username,
                    disable_secure_transport=True,
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
                    private_ip_address=db_server_postgresql.private_ip_address,
                    record_name="postgresql",
                    resource_group_name=props.resource_group_name,
                ),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=db_server_postgresql)
                ),
            )
