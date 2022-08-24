# Standard library imports
import pathlib
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, dbforpostgresql, network, storage

# Local imports
from .file_share_file import FileShareFile, FileShareFileProps
from data_safe_haven.helpers import FileReader


class GuacamoleProps:
    """Properties for GuacamoleComponent"""

    def __init__(
        self,
        aad_tenant_id: Input[str],
        aad_application_id: Input[str],
        aad_application_url: Input[str],
        ip_address_container: Input[str],
        ip_address_postgresql: Input[str],
        postgresql_password: Input[str],
        resource_group_name: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group: Input[str],
        virtual_network: Input[network.VirtualNetwork],
        virtual_network_resource_group_name: Input[str],
        postgresql_username: Optional[Input[str]] = "postgresadmin",
        subnet_container_name: Optional[Input[str]] = "GuacamoleContainersSubnet",
        subnet_database_name: Optional[Input[str]] = "GuacamoleDatabaseSubnet",
    ):
        self.aad_tenant_id = aad_tenant_id
        self.aad_application_id = aad_application_id
        self.aad_application_url = aad_application_url
        self.ip_address_container = ip_address_container
        self.ip_address_postgresql = ip_address_postgresql
        self.postgresql_username = postgresql_username
        self.postgresql_password = postgresql_password
        self.resource_group_name = resource_group_name
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group = storage_account_resource_group
        self.subnet_container_name = subnet_container_name
        self.subnet_database_name = subnet_database_name
        self.virtual_network = virtual_network
        self.virtual_network_resource_group_name = virtual_network_resource_group_name


class GuacamoleComponent(ComponentResource):
    """Deploy Guacamole with Pulumi"""

    def __init__(self, name: str, props: GuacamoleProps, opts: ResourceOptions = None):
        super().__init__("dsh:guacamole:GuacamoleComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Retrieve existing resources
        snet_guacamole_containers = network.get_subnet_output(
            subnet_name=props.subnet_container_name,
            resource_group_name=props.virtual_network_resource_group_name,
            virtual_network_name=props.virtual_network.name,
        )
        snet_guacamole_db = network.get_subnet_output(
            subnet_name=props.subnet_database_name,
            resource_group_name=props.virtual_network_resource_group_name,
            virtual_network_name=props.virtual_network.name,
        )
        storage_account_keys = storage.list_storage_account_keys(
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group,
        )
        storage_account_key_secret = Output.secret(storage_account_keys.keys[0].value)

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
            resource_group_name=props.resource_group_name,
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
            resource_group_name=props.virtual_network_resource_group_name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(depends_on=[props.virtual_network])
            ),
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
                # Note that the environment variables are not all documented.
                # More information at https://github.com/apache/guacamole-client/blob/master/guacamole-docker/bin/start.sh
                containerinstance.ContainerArgs(
                    image="guacamole/guacamole:1.4.0",
                    name=f"container-{self._name}-guacamole-guacamole",
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="GUACD_HOSTNAME", value="localhost"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LOGBACK_LEVEL", value="debug"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="OPENID_AUTHORIZATION_ENDPOINT",
                            value=f"https://login.microsoftonline.com/{props.aad_tenant_id}/oauth2/v2.0/authorize",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="OPENID_CLIENT_ID",
                            value=props.aad_application_id,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="OPENID_ISSUER",
                            value=f"https://login.microsoftonline.com/{props.aad_tenant_id}/v2.0",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="OPENID_JWKS_ENDPOINT",
                            value=f"https://login.microsoftonline.com/{props.aad_tenant_id}/discovery/v2.0/keys",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="OPENID_REDIRECT_URI", value=props.aad_application_url
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="OPENID_USERNAME_CLAIM_TYPE",
                            # value="name", # this is 'GivenName Surname'
                            value="preferred_username",  # this is 'username@domain'
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
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="GUACD_LOG_LEVEL", value="debug"
                        ),
                    ],
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

        # Upload Caddyfile
        resources_path = pathlib.Path(__file__).parent.parent.parent / "resources"
        reader = FileReader(resources_path / "guacamole" / "caddy" / "Caddyfile")
        caddyfile = FileShareFile(
            f"{self._name}/guacamole/caddy/{reader.name}",
            FileShareFileProps(
                destination_path=reader.name,
                share_name=file_share_caddy.name,
                file_contents=reader.file_contents_secret(),
                storage_account_key=storage_account_key_secret,
                storage_account_name=props.storage_account_name,
            ),
            opts=child_opts,
        )

        # Register outputs
        self.container_group_ip = container_group.ip_address.ip
        self.container_group_name = container_group.name
        self.postgresql_server_name = postgresql_server.name
        self.resource_group_name = Output.from_input(props.resource_group_name)
