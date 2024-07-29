from collections.abc import Mapping, Sequence

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import dbforpostgresql, network

from data_safe_haven.infrastructure.common import get_ip_addresses_from_private_endpoint


class PostgresqlDatabaseProps:
    """Properties for PostgresqlDatabaseComponent"""

    def __init__(
        self,
        *,
        database_names: Input[Sequence[str]],
        database_password: Input[str],
        database_resource_group_name: Input[str],
        database_server_name: Input[str],
        database_subnet_id: Input[str],
        database_username: Input[str],
        disable_secure_transport: bool,
        location: Input[str],
    ) -> None:
        self.database_names = Output.from_input(database_names)
        self.database_password = Output.secret(database_password)
        self.database_resource_group_name = database_resource_group_name
        self.database_server_name = database_server_name
        self.database_subnet_id = database_subnet_id
        self.database_username = database_username
        self.disable_secure_transport = disable_secure_transport
        self.location = location


class PostgresqlDatabaseComponent(ComponentResource):
    """Deploy PostgreSQL database server with Pulumi"""

    def __init__(
        self,
        name: str,
        props: PostgresqlDatabaseProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:common:PostgresqlDatabaseComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Define a PostgreSQL server
        db_server = dbforpostgresql.Server(
            f"{self._name}_server",
            administrator_login=props.database_username,
            administrator_login_password=props.database_password,
            auth_config=dbforpostgresql.AuthConfigArgs(
                active_directory_auth=dbforpostgresql.ActiveDirectoryAuthEnum.DISABLED,
                password_auth=dbforpostgresql.PasswordAuthEnum.ENABLED,
            ),
            backup=dbforpostgresql.BackupArgs(
                backup_retention_days=7,
                geo_redundant_backup=dbforpostgresql.GeoRedundantBackupEnum.DISABLED,
            ),
            create_mode=dbforpostgresql.CreateMode.DEFAULT,
            data_encryption=dbforpostgresql.DataEncryptionArgs(
                type=dbforpostgresql.ArmServerKeyType.SYSTEM_MANAGED,
            ),
            high_availability=dbforpostgresql.HighAvailabilityArgs(
                mode=dbforpostgresql.HighAvailabilityMode.DISABLED,
            ),
            location=props.location,
            resource_group_name=props.database_resource_group_name,
            server_name=props.database_server_name,
            sku=dbforpostgresql.SkuArgs(
                name="Standard_B2s",
                tier=dbforpostgresql.SkuTier.BURSTABLE,
            ),
            storage=dbforpostgresql.StorageArgs(
                storage_size_gb=32,
            ),
            version=dbforpostgresql.ServerVersion.SERVER_VERSION_14,
            opts=child_opts,
            tags=child_tags,
        )
        # Configure require_secure_transport
        if props.disable_secure_transport:
            dbforpostgresql.Configuration(
                f"{self._name}_secure_transport_configuration",
                configuration_name="require_secure_transport",
                resource_group_name=props.database_resource_group_name,
                server_name=db_server.name,
                source="user-override",
                value="OFF",
                opts=ResourceOptions.merge(
                    child_opts,
                    # Pulumi workaround for being unable to delete Configuration
                    # resource
                    # https://github.com/pulumi/pulumi-azure-native/issues/3072
                    ResourceOptions(parent=db_server, retain_on_delete=True),
                ),
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
            location=props.location,
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
            tags=child_tags,
        )

        # Register outputs
        self.db_server = db_server
        self.private_endpoint = private_endpoint
        self.private_ip_address = get_ip_addresses_from_private_endpoint(
            private_endpoint
        ).apply(lambda ips: ips[0])
