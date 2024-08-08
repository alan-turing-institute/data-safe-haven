from collections.abc import Mapping, Sequence

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, sql

from data_safe_haven.infrastructure.common import get_ip_addresses_from_private_endpoint


class MicrosoftSQLDatabaseProps:
    """Properties for MicrosoftSQLDatabaseComponent"""

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


class MicrosoftSQLDatabaseComponent(ComponentResource):
    """Deploy a Microsoft SQL database server with Pulumi"""

    def __init__(
        self,
        name: str,
        props: MicrosoftSQLDatabaseProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:common:MicrosoftSQLDatabaseComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Define a Microsoft SQL server
        db_server = sql.Server(
            f"{self._name}_server",
            administrator_login=props.database_username,
            administrator_login_password=props.database_password,
            location=props.location,
            minimal_tls_version=None,
            public_network_access=sql.ServerNetworkAccessFlag.DISABLED,
            resource_group_name=props.database_resource_group_name,
            server_name=props.database_server_name,
            version="12.0",
            opts=child_opts,
            tags=child_tags,
        )

        # Add any databases that are requested
        props.database_names.apply(
            lambda db_names: [
                sql.Database(
                    f"{self._name}_db_{db_name}",
                    database_name=db_name,
                    location=props.location,
                    resource_group_name=props.database_resource_group_name,
                    server_name=db_server.name,
                    sku=sql.SkuArgs(
                        capacity=1,
                        family="Gen5",
                        name="GP_S_Gen5",
                    ),
                    opts=ResourceOptions.merge(
                        child_opts, ResourceOptions(parent=db_server)
                    ),
                    tags=child_tags,
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
                    group_ids=["sqlServer"],
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
