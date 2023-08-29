from collections.abc import Sequence

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import dbforpostgresql, network

from data_safe_haven.infrastructure.common import get_ip_addresses_from_private_endpoint


class PostgresqlDatabaseProps:
    """Properties for PostgresqlDatabaseComponent"""

    def __init__(
        self,
        database_names: Input[Sequence[str]],
        database_password: Input[str],
        database_resource_group_name: Input[str],
        database_server_name: Input[str],
        database_subnet_id: Input[str],
        database_username: Input[str],
        location: Input[str],
    ) -> None:
        self.database_names = Output.from_input(database_names)
        self.database_password = database_password
        self.database_resource_group_name = database_resource_group_name
        self.database_server_name = database_server_name
        self.database_subnet_id = database_subnet_id
        self.database_username = database_username
        self.location = location


class PostgresqlDatabaseComponent(ComponentResource):
    """Deploy PostgreSQL database server with Pulumi"""

    def __init__(
        self,
        name: str,
        props: PostgresqlDatabaseProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:common:PostgresqlDatabaseComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        # Define a PostgreSQL server
        db_server = dbforpostgresql.Server(
            f"{self._name}_server",
            location=props.location,
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
            resource_group_name=props.database_resource_group_name,
            server_name=props.database_server_name,
            sku=dbforpostgresql.SkuArgs(
                capacity=2,
                family="Gen5",
                name="GP_Gen5_2",
                tier=dbforpostgresql.SkuTier.GENERAL_PURPOSE,  # required to use private link
            ),
            opts=child_opts,
        )
        # Add any databases that are requested
        props.database_names.apply(
            lambda db_names: [
                dbforpostgresql.Database(
                    f"{self._name}_db_{db_name}",
                    charset="UTF8",
                    database_name=db_name,
                    resource_group_name=props.database_resource_group_name,
                    server_name=db_server.name,
                    opts=ResourceOptions.merge(
                        child_opts, ResourceOptions(parent=db_server)
                    ),
                )
                for db_name in db_names
            ]
        )
        # Deploy a private endpoint for the PostgreSQL server
        private_endpoint = network.PrivateEndpoint(
            f"{self._name}_private_endpoint",
            private_endpoint_name=Output.concat(
                props.database_server_name, "-endpoint"
            ),
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["postgresqlServer"],
                    name=Output.concat(props.database_server_name, "-privatelink"),
                    private_link_service_connection_state=network.PrivateLinkServiceConnectionStateArgs(
                        actions_required="None",
                        description="Auto-approved",
                        status="Approved",
                    ),
                    private_link_service_id=db_server.id,
                )
            ],
            resource_group_name=props.database_resource_group_name,
            subnet=network.SubnetArgs(id=props.database_subnet_id),
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=db_server)),
        )

        # Register outputs
        self.db_server = db_server
        self.private_endpoint = private_endpoint
        self.private_ip_address = get_ip_addresses_from_private_endpoint(
            private_endpoint
        ).apply(lambda ips: ips[0])
