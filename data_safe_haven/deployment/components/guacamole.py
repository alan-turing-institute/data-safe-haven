# Standard library imports
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, ResourceOptions
from pulumi_azure_native import containerinstance, dbforpostgresql, network, storage


class GuacamoleProps:
    """Properties for GuacamoleComponent"""

    def __init__(
        self,
        ip_address_container: Input[str],
        ip_address_postgresql: Input[str],
        postgresql_password: Input[str],
        resource_group_name: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group: Input[str],
        virtual_network_name: Input[str],
        virtual_network_resource_group: Input[str],
        subnet_container_name: Optional[Input[str]] = "GuacamoleContainersSubnet",
        subnet_database_name: Optional[Input[str]] = "GuacamoleDatabaseSubnet",
    ):
        self.ip_address_container = ip_address_container
        self.ip_address_postgresql = ip_address_postgresql
        self.postgresql_password = postgresql_password
        self.resource_group_name = resource_group_name
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group = storage_account_resource_group
        self.subnet_container_name = subnet_container_name
        self.subnet_database_name = subnet_database_name
        self.virtual_network_name = virtual_network_name
        self.virtual_network_resource_group = virtual_network_resource_group


class GuacamoleComponent(ComponentResource):
    """Deploy Guacamole with Pulumi"""

    def __init__(self, name: str, props: GuacamoleProps, opts: ResourceOptions = None):
        super().__init__("dsh:Guacamole", name, {}, opts)

        # Retrieve existing resources
        snet_guacamole_containers = network.get_subnet(
            subnet_name=props.subnet_container_name,
            resource_group_name=props.virtual_network_resource_group,
            virtual_network_name=props.virtual_network_name,
        )
        snet_guacamole_db = network.get_subnet(
            subnet_name=props.subnet_database_name,
            resource_group_name=props.virtual_network_resource_group,
            virtual_network_name=props.virtual_network_name,
        )
        storage_account_keys = storage.list_storage_account_keys(
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group,
        )

        # Define configuration file shares
        self.file_share_caddy = storage.FileShare(
            "file_share_guacamole_caddy",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group,
            share_name="guacamole-caddy",
            share_quota=5120,
        )

        # Define a PostgreSQL server
        postgresql_server = dbforpostgresql.Server(
            "postgresql_server",
            location="uksouth",
            properties={
                "administratorLogin": "guacamole",
                "administratorLoginPassword": props.postgresql_password,
                "infrastructureEncryption": "Disabled",
                "minimalTlsVersion": "TLSEnforcementDisabled",
                "publicNetworkAccess": "Disabled",
                "sslEnforcement": "Enabled",
                "storageProfile": {
                    "backupRetentionDays": 7,
                    "geoRedundantBackup": "Disabled",
                    "storageAutogrow": "Enabled",
                    "storageMB": 5120,
                },
                "version": "11",
            },
            resource_group_name="rg-v4example-guacamole",
            server_name=f"postgresql-{self._name}-guacamole",
            sku=dbforpostgresql.SkuArgs(
                capacity=2,
                family="Gen5",
                name="GP_Gen5_2",
                tier="GeneralPurpose",  # required to use private link
            ),
        )
        postgresql_private_endpoint = network.PrivateEndpoint(
            "postgresql_private_endpoint",
            custom_dns_configs=[
                network.CustomDnsConfigPropertiesFormatArgs(
                    ip_addresses=[props.ip_address_postgresql],
                )
            ],
            private_endpoint_name=f"endpoint-{self._name}-guacamole-db",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["postgresqlServer"],
                    name=f"privatelink-{self._name}-guacamole-db",
                    private_link_service_connection_state=network.PrivateLinkServiceConnectionStateArgs(
                        actions_required="None",
                        description="Auto-approved",
                        status="Approved",
                    ),
                    private_link_service_id=postgresql_server.id,
                )
            ],
            resource_group_name=props.resource_group_name,
            subnet=network.SubnetArgs(id=snet_guacamole_db.id),
        )
        postgresql_database = dbforpostgresql.Database(
            "database",
            charset="UTF8",
            collation="en_GB.utf8",
            database_name="guacamole",
            resource_group_name=props.resource_group_name,
            server_name=postgresql_server.name,
        )

        # Define a network profile
        network_profile_guacamole = network.NetworkProfile(
            "network_profile_guacamole",
            container_network_interface_configurations=[
                network.ContainerNetworkInterfaceConfigurationArgs(
                    ip_configurations=[
                        network.IPConfigurationProfileArgs(
                            name="ipconfigguacamole",
                            subnet=network.SubnetArgs(
                                id=snet_guacamole_containers.id,
                            ),
                        )
                    ],
                    name="networkinterfaceconfigguacamole",
                )
            ],
            network_profile_name=f"np-{self._name}-guacamole",
            resource_group_name=props.virtual_network_resource_group,
        )

        # Define the container group with guacd and guacamole
        self.container_group = containerinstance.ContainerGroup(
            "container_group_guacamole",
            container_group_name=f"container-{self._name}-guacamole",
            containers=[
                containerinstance.ContainerArgs(
                    image="caddy:latest",
                    name=f"container-{self._name}-guacamole-caddy",
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=80,
                            protocol="TCP",
                        )
                    ],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=1,
                            memory_in_gb=1.5,
                        ),
                    ),
                    volume_mounts=[
                        containerinstance.VolumeMountArgs(
                            mount_path="/etc/caddy",
                            name="guacamole-caddy-config",
                            read_only=False,
                        ),
                    ],
                ),
                containerinstance.ContainerArgs(
                    image="guacamole/guacamole:1.3.0",
                    name=f"container-{self._name}-guacamole-guacamole",
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="GUACD_HOSTNAME", value="guacd"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LOGBACK_LEVEL", value="debug"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_HOSTNAME", value="postgres"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_DATABASE", value="guacamole"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_USER", value="guacamole"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_PASSWORD",
                            secure_value=props.postgresql_password,
                        ),
                    ],
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=8080,
                            protocol="TCP",
                        )
                    ],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=1,
                            memory_in_gb=1.5,
                        ),
                    ),
                ),
                containerinstance.ContainerArgs(
                    image="guacamole/guacd:1.3.0",
                    name=f"container-{self._name}-guacamole-guacd",
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=4822,
                            protocol="TCP",
                        )
                    ],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=1,
                            memory_in_gb=1.5,
                        ),
                    ),
                ),
            ],
            ip_address=containerinstance.IpAddressArgs(
                ip=props.ip_address_container,
                ports=[
                    containerinstance.PortArgs(
                        port=80,
                        protocol="TCP",
                    )
                ],
                type="Private",
            ),
            network_profile=containerinstance.ContainerGroupNetworkProfileArgs(
                id=network_profile_guacamole.id,
            ),
            os_type="Linux",
            resource_group_name=props.resource_group_name,
            restart_policy="Always",
            sku="Standard",
            volumes=[
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=self.file_share_caddy.name,
                        storage_account_key=storage_account_keys.keys[0].value,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="guacamole-caddy-config",
                ),
            ],
        )
