# Standard library imports
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, dbforpostgresql, network, storage


class GuacamoleProps:
    """Properties for GuacamoleComponent"""

    def __init__(
        self,
        ip_address_container: Input[str],
        ip_address_postgresql: Input[str],
        ldap_group_base_dn: Input[str],
        ldap_search_user_id: Input[str],
        ldap_search_user_password: Input[str],
        ldap_server_ip: Input[str],
        ldap_user_base_dn: Input[str],
        postgresql_password: Input[str],
        resource_group_name: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group: Input[str],
        virtual_network_name: Input[str],
        virtual_network_resource_group: Input[str],
        postgresql_username: Optional[Input[str]] = "postgresadmin",
        subnet_container_name: Optional[Input[str]] = "GuacamoleContainersSubnet",
        subnet_database_name: Optional[Input[str]] = "GuacamoleDatabaseSubnet",
    ):
        self.ip_address_container = ip_address_container
        self.ip_address_postgresql = ip_address_postgresql
        self.ldap_group_base_dn = ldap_group_base_dn
        self.ldap_search_user_id = ldap_search_user_id
        self.ldap_search_user_password = ldap_search_user_password
        self.ldap_server_ip = ldap_server_ip
        self.ldap_user_base_dn = ldap_user_base_dn
        self.postgresql_username = postgresql_username
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
        super().__init__("dsh:guacamole:GuacamoleComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

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
        file_share_caddy = storage.FileShare(
            "file_share_guacamole_caddy",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group,
            share_name="guacamole-caddy",
            share_quota=5120,
            opts=child_opts,
        )

        # Define a PostgreSQL server
        postgresql_server_name = f"postgresql-{self._name}-guacamole"
        postgresql_server = dbforpostgresql.Server(
            "postgresql_server",
            properties={
                "administratorLogin": props.postgresql_username,
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
            server_name=postgresql_server_name,
            sku=dbforpostgresql.SkuArgs(
                capacity=2,
                family="Gen5",
                name="GP_Gen5_2",
                tier="GeneralPurpose",  # required to use private link
            ),
            opts=child_opts,
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
            opts=child_opts,
        )
        postgresql_database = dbforpostgresql.Database(
            "database",
            charset="UTF8",
            database_name="guacamole",
            resource_group_name=props.resource_group_name,
            server_name=postgresql_server.name,
            opts=child_opts,
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
            opts=child_opts,
        )

        # Define the container group with guacd and guacamole
        container_group = containerinstance.ContainerGroup(
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
                    image="guacamole/guacamole:1.4.0",
                    name=f"container-{self._name}-guacamole-guacamole",
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="GUACD_HOSTNAME", value="localhost"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_HOSTNAME", value=props.ldap_server_ip
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_PORT", value="1389"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_USER_BASE_DN", value=props.ldap_user_base_dn
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_USERNAME_ATTRIBUTE", value="uid"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_GROUP_BASE_DN", value=props.ldap_group_base_dn
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_SEARCH_BIND_DN",
                            value=Output.concat(
                                "uid=",
                                props.ldap_search_user_id,
                                ",",
                                props.ldap_user_base_dn,
                            ),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_SEARCH_BIND_PASSWORD",
                            secure_value=props.ldap_search_user_password,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LOGBACK_LEVEL", value="debug"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_DATABASE", value="guacamole"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_HOSTNAME", value=props.ip_address_postgresql
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_PASSWORD",
                            secure_value=props.postgresql_password,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRESQL_SSL_MODE", value="require"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_USER",
                            value=f"{props.postgresql_username}@{postgresql_server_name}",
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
                    image="guacamole/guacd:1.4.0",
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
                        share_name=file_share_caddy.name,
                        storage_account_key=storage_account_keys.keys[0].value,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="guacamole-caddy-config",
                ),
            ],
            opts=child_opts,
        )

        # Register outputs
        self.container_group_name = container_group.name
        self.file_share_caddy_name = file_share_caddy.name
        self.postgresql_server_name = postgresql_server.name
        self.private_ip_address = Output.from_input(props.ip_address_container)
        self.resource_group_name = Output.from_input(props.resource_group_name)
