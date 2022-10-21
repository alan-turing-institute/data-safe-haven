"""Pulumi component for SRE remote desktop"""
# Standard library imports
import pathlib
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import (
    containerinstance,
    dbforpostgresql,
    network,
    resources,
    storage,
)

# Local imports
from data_safe_haven.helpers import FileReader
from ..dynamic.azuread_application import AzureADApplication, AzureADApplicationProps
from ..dynamic.file_share_file import FileShareFile, FileShareFileProps


class SRERemoteDesktopProps:
    """Properties for SRERemoteDesktopComponent"""

    def __init__(
        self,
        aad_application_name: Input[str],
        aad_application_fqdn: Input[str],
        aad_auth_token: Input[str],
        aad_tenant_id: Input[str],
        ip_address_container: Input[str],
        ip_address_database: Input[str],
        database_password: Input[str],
        location: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group: Input[str],
        subnet_container_name: Input[str],
        subnet_database_name: Input[str],
        virtual_network: Input[network.VirtualNetwork],
        virtual_network_resource_group_name: Input[str],
        database_username: Optional[Input[str]] = "postgresadmin",
    ):
        self.aad_application_name = aad_application_name
        self.aad_application_url = Output.from_input(aad_application_fqdn).apply(
            lambda fqdn: f"https://{fqdn}"
        )
        self.aad_auth_token = aad_auth_token
        self.aad_tenant_id = aad_tenant_id
        self.ip_address_container = ip_address_container
        self.ip_address_database = ip_address_database
        self.database_password = database_password
        self.database_username = database_username
        self.location = location
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group = storage_account_resource_group
        self.subnet_container_name = subnet_container_name
        self.subnet_database_name = subnet_database_name
        self.virtual_network = virtual_network
        self.virtual_network_resource_group_name = virtual_network_resource_group_name


class SRERemoteDesktopComponent(ComponentResource):
    """Deploy remote desktop gateway with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SRERemoteDesktopProps,
        opts: ResourceOptions = None,
    ):
        super().__init__("dsh:sre:SRERemoteDesktopComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"rg-{stack_name}-remote-desktop",
        )

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

        # Define AzureAD application
        aad_application = AzureADApplication(
            f"{self._name}_aad_application",
            AzureADApplicationProps(
                application_name=props.aad_application_name,
                application_url=props.aad_application_url,
                auth_token=props.aad_auth_token,
            ),
            opts=child_opts,
        )

        # Define configuration file shares
        file_share = storage.FileShare(
            f"{self._name}_file_share",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group,
            share_name="remote-desktop-caddy",
            share_quota=5120,
            opts=child_opts,
        )

        # Upload Caddyfile
        resources_path = pathlib.Path(__file__).parent.parent.parent / "resources"
        reader = FileReader(resources_path / "remote_desktop" / "caddy" / "Caddyfile")
        caddyfile = FileShareFile(
            f"{self._name}_file_share_caddyfile",
            FileShareFileProps(
                destination_path=reader.name,
                share_name=file_share.name,
                file_contents=Output.secret(reader.file_contents()),
                storage_account_key=storage_account_key_secret,
                storage_account_name=props.storage_account_name,
            ),
            opts=child_opts,
        )

        # Define a PostgreSQL server
        connection_db_server_name = f"postgresql-{stack_name}-guacamole"
        connection_db_server = dbforpostgresql.Server(
            f"{self._name}_connection_db_server",
            properties={
                "administratorLogin": props.database_username,
                "administratorLoginPassword": props.database_password,
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
            resource_group_name=resource_group.name,
            server_name=connection_db_server_name,
            sku=dbforpostgresql.SkuArgs(
                capacity=2,
                family="Gen5",
                name="GP_Gen5_2",
                tier="GeneralPurpose",  # required to use private link
            ),
            opts=child_opts,
        )
        connection_db_private_endpoint = network.PrivateEndpoint(
            f"{self._name}_connection_db_private_endpoint",
            custom_dns_configs=[
                network.CustomDnsConfigPropertiesFormatArgs(
                    ip_addresses=[props.ip_address_database],
                )
            ],
            private_endpoint_name=f"endpoint-{stack_name}-guacamole-db",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["postgresqlServer"],
                    name=f"privatelink-{stack_name}-guacamole-db",
                    private_link_service_connection_state=network.PrivateLinkServiceConnectionStateArgs(
                        actions_required="None",
                        description="Auto-approved",
                        status="Approved",
                    ),
                    private_link_service_id=connection_db_server.id,
                )
            ],
            resource_group_name=resource_group.name,
            subnet=network.SubnetArgs(id=snet_guacamole_db.id),
            opts=child_opts,
        )
        connection_db = dbforpostgresql.Database(
            f"{self._name}_connection_db",
            charset="UTF8",
            database_name="guacamole",
            resource_group_name=resource_group.name,
            server_name=connection_db_server.name,
            opts=child_opts,
        )

        # Define a network profile
        container_network_profile = network.NetworkProfile(
            f"{self._name}_container_network_profile",
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
            network_profile_name=f"np-{stack_name}-guacamole",
            resource_group_name=props.virtual_network_resource_group_name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(depends_on=[props.virtual_network])
            ),
        )

        # Define the container group with guacd, guacamole and caddy
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"container-{stack_name}-remote-desktop",
            containers=[
                containerinstance.ContainerArgs(
                    image="caddy:latest",
                    name=f"container-{stack_name[:32]}-remote-desktop-caddy",  # maximum of 63 characters
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
                    name=f"container-{stack_name[:28]}-remote-desktop-guacamole",  # maximum of 63 characters
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
                            value=aad_application.application_id,
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
                            value="preferred_username",  # this is 'username@domain'
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_DATABASE", value="guacamole"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_HOSTNAME", value=props.ip_address_database
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_PASSWORD",
                            secure_value=props.database_password,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRESQL_SSL_MODE", value="require"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_USER",
                            value=f"{props.database_username}@{connection_db_server_name}",
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
                    name=f"container-{stack_name[:32]}-remote-desktop-guacd",  # maximum of 63 characters
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
                id=container_network_profile.id,
            ),
            os_type="Linux",
            resource_group_name=resource_group.name,
            restart_policy="Always",
            sku="Standard",
            volumes=[
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=file_share.name,
                        storage_account_key=storage_account_keys.keys[0].value,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="guacamole-caddy-config",
                ),
            ],
            opts=child_opts,
        )

        # Register outputs
        self.resource_group_name = resource_group.name

        # Register exports
        self.exports = {
            "connection_db_name": connection_db.name,
            "connection_db_server_name": connection_db_server_name,
            "container_group_name": container_group.name,
            "container_ip_address": Output.from_input(props.ip_address_container),
            "resource_group_name": resource_group.name,
        }
