from pulumi import ComponentResource, Input, ResourceOptions
from pulumi_azure_native import dbforpostgresql, network

from data_safe_haven.utility import DatabaseSystem


class SREDatabaseServerProps:
    """Properties for SREDatabaseServerComponent"""

    def __init__(
        self,
        database_password: Input[str],
        database_system: DatabaseSystem,  # this must *not* be passed as an Input[T]
        resource_group_name: Input[str],
        subnet_id: Input[str],
        database_username: Input[str] | None = None,
    ) -> None:
        self.database_password = database_password
        self.database_system = database_system
        self.database_username = (
            database_username if database_username else "databaseadmin"
        )
        self.resource_group_name = resource_group_name
        self.subnet_id = subnet_id


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
            db_server_postgresql_name = f"{stack_name}-db-server-postgresql"
            db_server_postgresql = dbforpostgresql.Server(
                f"{self._name}_db_server_postgresql",
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
                server_name=db_server_postgresql_name,
                sku=dbforpostgresql.SkuArgs(
                    capacity=2,
                    family="Gen5",
                    name="GP_Gen5_2",
                    tier=dbforpostgresql.SkuTier.GENERAL_PURPOSE,  # required to use private link
                ),
                opts=child_opts,
            )
            # Deploy a private endpoint to the PostgreSQL server
            network.PrivateEndpoint(
                f"{self._name}_db_server_postgresql_private_endpoint",
                private_endpoint_name=f"{stack_name}-endpoint-db-server-postgresql",
                private_link_service_connections=[
                    network.PrivateLinkServiceConnectionArgs(
                        group_ids=["postgresqlServer"],
                        name=f"{stack_name}-privatelink-db-server-postgresql",
                        private_link_service_connection_state=network.PrivateLinkServiceConnectionStateArgs(
                            actions_required="None",
                            description="Auto-approved",
                            status="Approved",
                        ),
                        private_link_service_id=db_server_postgresql.id,
                    )
                ],
                resource_group_name=props.resource_group_name,
                subnet=network.SubnetArgs(id=props.subnet_id),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=db_server_postgresql)
                ),
            )
