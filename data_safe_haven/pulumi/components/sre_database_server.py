from pulumi import ComponentResource, Input, ResourceOptions
from pulumi_azure_native import dbforpostgresql

from data_safe_haven.utility import DatabaseSystem


class SREDatabaseServerProps:
    """Properties for SREDatabaseServerComponent"""

    def __init__(
        self,
        database_password: Input[str],
        database_system: DatabaseSystem,  # this must *not* be passed as an Input[T]
        database_username: Input[str],
        resource_group_name: Input[str],
    ) -> None:
        self.database_password = database_password
        self.database_system = database_system
        self.database_username = database_username
        self.resource_group_name = resource_group_name


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
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        if props.database_system == DatabaseSystem.POSTGRESQL:
            # Define a PostgreSQL server
            postgresql_db_server_name = f"{stack_name}-db-server-postgresql-service"
            dbforpostgresql.Server(
                f"{self._name}_db_server_postgresql_service",
                properties=dbforpostgresql.ServerPropertiesForDefaultCreateArgs(
                    administrator_login=props.database_username,
                    administrator_login_password=props.database_password,
                    create_mode="Default",
                    infrastructure_encryption=dbforpostgresql.InfrastructureEncryption.DISABLED,
                    minimal_tls_version=dbforpostgresql.MinimalTlsVersionEnum.TLS_ENFORCEMENT_DISABLED,
                    public_network_access=dbforpostgresql.PublicNetworkAccessEnum.DISABLED,
                    ssl_enforcement=dbforpostgresql.SslEnforcementEnum.ENABLED,
                    storage_profile=dbforpostgresql.StorageProfileArgs(
                        backup_retention_days=7,
                        geo_redundant_backup=dbforpostgresql.GeoRedundantBackup.DISABLED,
                        storage_autogrow=dbforpostgresql.StorageAutogrow.ENABLED,
                        storage_mb=5120,
                    ),
                    version=dbforpostgresql.ServerVersion.SERVER_VERSION_11,
                ),
                resource_group_name=props.resource_group_name,
                server_name=postgresql_db_server_name,
                sku=dbforpostgresql.SkuArgs(
                    capacity=2,
                    family="Gen5",
                    name="GP_Gen5_2",
                    tier=dbforpostgresql.SkuTier.GENERAL_PURPOSE,  # required to use private link
                ),
                opts=child_opts,
            )
