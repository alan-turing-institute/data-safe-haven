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
from data_safe_haven.external.interface import AzureIPv4Range
from data_safe_haven.helpers import FileReader
from data_safe_haven.pulumi.common.transformations import (
    get_id_from_subnet,
    get_name_from_rg,
)
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
        allow_copy: Input[bool],
        allow_paste: Input[bool],
        database_password: Input[str],
        location: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
        subnet_guacamole_containers: Input[network.GetSubnetResult],
        subnet_guacamole_database: Input[network.GetSubnetResult],
        virtual_network: Input[network.VirtualNetwork],
        virtual_network_resource_group: Input[resources.ResourceGroup],
        database_username: Optional[Input[str]] = "postgresadmin",
    ):
        self.aad_application_name = aad_application_name
        self.aad_application_url = Output.concat("https://", aad_application_fqdn)
        self.aad_auth_token = aad_auth_token
        self.aad_tenant_id = aad_tenant_id
        self.database_password = database_password
        self.database_username = database_username
        self.disable_copy = not allow_copy
        self.disable_paste = not allow_paste
        self.location = location
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group_name = storage_account_resource_group_name
        self.subnet_guacamole_containers_id = Output.from_input(
            subnet_guacamole_containers
        ).apply(get_id_from_subnet)
        self.subnet_guacamole_containers_ip_addresses = Output.from_input(
            subnet_guacamole_containers
        ).apply(
            lambda s: [
                str(ip) for ip in AzureIPv4Range.from_cidr(s.address_prefix).available()
            ]
            if s.address_prefix
            else []
        )
        self.subnet_guacamole_database_id = Output.from_input(
            subnet_guacamole_database
        ).apply(get_id_from_subnet)
        self.subnet_guacamole_database_ip_addresses = Output.from_input(
            subnet_guacamole_database
        ).apply(
            lambda s: [
                str(ip) for ip in AzureIPv4Range.from_cidr(s.address_prefix).available()
            ]
            if s.address_prefix
            else []
        )
        self.virtual_network = virtual_network
        self.virtual_network_resource_group_name = Output.from_input(
            virtual_network_resource_group
        ).apply(get_name_from_rg)


class SRERemoteDesktopComponent(ComponentResource):
    """Deploy remote desktop gateway with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SRERemoteDesktopProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:sre:SRERemoteDesktopComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-remote-desktop",
            opts=child_opts,
        )

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
            resource_group_name=props.storage_account_resource_group_name,
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
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=child_opts,
        )

        # Define a PostgreSQL server
        connection_db_server_name = f"{stack_name}-db-postgresql-guacamole"
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
                tier=dbforpostgresql.SkuTier.GENERAL_PURPOSE,  # required to use private link
            ),
            opts=child_opts,
        )
        connection_db_private_endpoint = network.PrivateEndpoint(
            f"{self._name}_connection_db_private_endpoint",
            custom_dns_configs=[
                network.CustomDnsConfigPropertiesFormatArgs(
                    ip_addresses=[props.subnet_guacamole_database_ip_addresses[0]],
                )
            ],
            private_endpoint_name=f"{stack_name}-endpoint-guacamole-db",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["postgresqlServer"],
                    name=f"{stack_name}-privatelink-guacamole-db",
                    private_link_service_connection_state=network.PrivateLinkServiceConnectionStateArgs(
                        actions_required="None",
                        description="Auto-approved",
                        status="Approved",
                    ),
                    private_link_service_id=connection_db_server.id,
                )
            ],
            resource_group_name=resource_group.name,
            subnet=network.SubnetArgs(id=props.subnet_guacamole_database_id),
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
                                id=props.subnet_guacamole_containers_id,
                            ),
                        )
                    ],
                    name="networkinterfaceconfigguacamole",
                )
            ],
            network_profile_name=f"{stack_name}-np-guacamole",
            resource_group_name=props.virtual_network_resource_group_name,
            opts=ResourceOptions.merge(
                ResourceOptions(depends_on=[props.virtual_network]), child_opts
            ),
        )

        # Define the container group with guacd, guacamole and caddy
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-remote-desktop",
            containers=[
                containerinstance.ContainerArgs(
                    image="caddy:latest",
                    name=f"{stack_name[:32]}-container-remote-desktop-caddy",  # maximum of 63 characters
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
                    name=f"{stack_name[:28]}-container-remote-desktop-guacamole",  # maximum of 63 characters
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
                            name="POSTGRES_HOSTNAME",
                            value=props.subnet_guacamole_database_ip_addresses[0],
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
                            protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
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
                    name=f"{stack_name[:32]}-container-remote-desktop-guacd",  # maximum of 63 characters
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="GUACD_LOG_LEVEL", value="debug"
                        ),
                    ],
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=4822,
                            protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
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
                ip=props.subnet_guacamole_containers_ip_addresses[0],
                ports=[
                    containerinstance.PortArgs(
                        port=80,
                        protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                    )
                ],
                type=containerinstance.ContainerGroupIpAddressType.PRIVATE,
            ),
            network_profile=containerinstance.ContainerGroupNetworkProfileArgs(
                id=container_network_profile.id,
            ),
            os_type=containerinstance.OperatingSystemTypes.LINUX,
            resource_group_name=resource_group.name,
            restart_policy=containerinstance.ContainerGroupRestartPolicy.ALWAYS,
            sku=containerinstance.ContainerGroupSku.STANDARD,
            volumes=[
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=file_share.name,
                        storage_account_key=props.storage_account_key,
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
            "container_ip_address": props.subnet_guacamole_containers_ip_addresses[0],
            "disable_copy": props.disable_copy,
            "disable_paste": props.disable_paste,
            "resource_group_name": resource_group.name,
        }
