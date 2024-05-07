"""Pulumi component for SRE remote desktop"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import (
    containerinstance,
    network,
    resources,
    storage,
)

from data_safe_haven.external import AzureIPv4Range
from data_safe_haven.infrastructure.common import (
    get_id_from_subnet,
)
from data_safe_haven.infrastructure.components import (
    AzureADApplication,
    AzureADApplicationProps,
    FileShareFile,
    FileShareFileProps,
    PostgresqlDatabaseComponent,
    PostgresqlDatabaseProps,
)
from data_safe_haven.resources import resources_path
from data_safe_haven.utility import FileReader


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
        dns_server_ip: Input[str],
        ldap_group_filter: Input[str],
        ldap_group_search_base: Input[str],
        ldap_server_hostname: Input[str],
        ldap_server_port: Input[int],
        ldap_user_filter: Input[str],
        ldap_user_search_base: Input[str],
        location: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
        subnet_guacamole_containers: Input[network.GetSubnetResult],
        subnet_guacamole_containers_support: Input[network.GetSubnetResult],
        database_username: Input[str] | None = "postgresadmin",
    ) -> None:
        self.aad_application_name = aad_application_name
        self.aad_application_url = Output.concat("https://", aad_application_fqdn)
        self.aad_auth_token = aad_auth_token
        self.aad_tenant_id = aad_tenant_id
        self.database_password = database_password
        self.database_username = (
            database_username if database_username else "postgresadmin"
        )
        self.disable_copy = not allow_copy
        self.disable_paste = not allow_paste
        self.dns_server_ip = dns_server_ip
        self.ldap_group_filter = ldap_group_filter
        self.ldap_group_search_base = ldap_group_search_base
        self.ldap_server_hostname = ldap_server_hostname
        self.ldap_server_port = ldap_server_port
        self.ldap_user_filter = ldap_user_filter
        self.ldap_user_search_base = ldap_user_search_base
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
            lambda s: (
                [
                    str(ip)
                    for ip in AzureIPv4Range.from_cidr(s.address_prefix).available()
                ]
                if s.address_prefix
                else []
            )
        )
        self.subnet_guacamole_containers_support_id = Output.from_input(
            subnet_guacamole_containers_support
        ).apply(get_id_from_subnet)
        self.subnet_guacamole_containers_support_ip_addresses = Output.from_input(
            subnet_guacamole_containers_support
        ).apply(
            lambda s: (
                [
                    str(ip)
                    for ip in AzureIPv4Range.from_cidr(s.address_prefix).available()
                ]
                if s.address_prefix
                else []
            )
        )


class SRERemoteDesktopComponent(ComponentResource):
    """Deploy remote desktop gateway with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SRERemoteDesktopProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:RemoteDesktopComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-remote-desktop",
            opts=child_opts,
            tags=child_tags,
        )

        # Define AzureAD application
        aad_application = AzureADApplication(
            f"{self._name}_aad_application",
            AzureADApplicationProps(
                application_name=props.aad_application_name,
                auth_token=props.aad_auth_token,
                web_redirect_url=props.aad_application_url,
            ),
            opts=child_opts,
        )

        # Define configuration file shares
        file_share = storage.FileShare(
            f"{self._name}_file_share",
            access_tier=storage.ShareAccessTier.COOL,
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="remote-desktop-caddy",
            share_quota=1,
            signed_identifiers=[],
            opts=child_opts,
        )

        # Upload Caddyfile
        reader = FileReader(resources_path / "remote_desktop" / "caddy" / "Caddyfile")
        FileShareFile(
            f"{self._name}_file_share_caddyfile",
            FileShareFileProps(
                destination_path=reader.name,
                share_name=file_share.name,
                file_contents=Output.secret(reader.file_contents()),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=file_share)),
        )

        # Define a PostgreSQL server to hold user and connection details
        db_guacamole_connections = "guacamole"
        db_server_guacamole = PostgresqlDatabaseComponent(
            f"{self._name}_db_guacamole",
            PostgresqlDatabaseProps(
                database_names=[db_guacamole_connections],
                database_password=props.database_password,
                database_resource_group_name=resource_group.name,
                database_server_name=f"{stack_name}-db-server-guacamole",
                database_subnet_id=props.subnet_guacamole_containers_support_id,
                database_username=props.database_username,
                location=props.location,
            ),
            opts=child_opts,
            tags=child_tags,
        )

        # Define the container group with guacd, guacamole and caddy
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-group-remote-desktop",
            containers=[
                containerinstance.ContainerArgs(
                    image="caddy:2.7.6",
                    name="caddy"[:63],
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=80,
                            protocol=containerinstance.ContainerNetworkProtocol.TCP,
                        )
                    ],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=0.5,
                            memory_in_gb=0.5,
                        ),
                    ),
                    volume_mounts=[
                        containerinstance.VolumeMountArgs(
                            mount_path="/etc/caddy",
                            name="caddy-etc-caddy",
                            read_only=False,
                        ),
                    ],
                ),
                # Note that the environment variables are not all documented.
                # More information at https://github.com/apache/guacamole-client/blob/master/guacamole-docker/bin/start.sh
                containerinstance.ContainerArgs(
                    image="guacamole/guacamole:1.5.5",
                    name="guacamole"[:63],
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="GUACD_HOSTNAME", value="localhost"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LOGBACK_LEVEL", value="debug"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="OPENID_AUTHORIZATION_ENDPOINT",
                            value=Output.concat(
                                "https://login.microsoftonline.com/",
                                props.aad_tenant_id,
                                "/oauth2/v2.0/authorize",
                            ),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="OPENID_CLIENT_ID",
                            value=aad_application.application_id,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="OPENID_ISSUER",
                            value=Output.concat(
                                "https://login.microsoftonline.com/",
                                props.aad_tenant_id,
                                "/v2.0",
                            ),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="OPENID_JWKS_ENDPOINT",
                            value=Output.concat(
                                "https://login.microsoftonline.com/",
                                props.aad_tenant_id,
                                "/discovery/v2.0/keys",
                            ),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="OPENID_REDIRECT_URI", value=props.aad_application_url
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="OPENID_USERNAME_CLAIM_TYPE",
                            value="preferred_username",  # this is 'username@domain'
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRESQL_DATABASE", value=db_guacamole_connections
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRESQL_HOSTNAME",
                            value=props.subnet_guacamole_containers_support_ip_addresses[
                                0
                            ],
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRESQL_PASSWORD",
                            secure_value=props.database_password,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRESQL_SSL_MODE", value="require"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRESQL_SOCKET_TIMEOUT", value="5"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRESQL_USER",
                            value=props.database_username,
                        ),
                    ],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=1,
                            memory_in_gb=1,
                        ),
                    ),
                ),
                containerinstance.ContainerArgs(
                    image="guacamole/guacd:1.5.5",
                    name="guacd"[:63],
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="GUACD_LOG_LEVEL", value="debug"
                        ),
                    ],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=1,
                            memory_in_gb=1,
                        ),
                    ),
                ),
                containerinstance.ContainerArgs(
                    image="ghcr.io/alan-turing-institute/guacamole-user-sync:v0.4.0",
                    name="guacamole-user-sync"[:63],
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_GROUP_BASE_DN",
                            value=props.ldap_group_search_base,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_GROUP_NAME_ATTR",
                            value="cn",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_GROUP_FILTER",
                            value=props.ldap_group_filter,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_HOST",
                            value=props.ldap_server_hostname,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_PORT",
                            value=Output.from_input(props.ldap_server_port).apply(str),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_USER_NAME_ATTR",
                            value="oauth_username",  # this is the name that users connect with
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_USER_BASE_DN",
                            value=props.ldap_user_search_base,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_USER_FILTER",
                            value=props.ldap_user_filter,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRESQL_DB_NAME",
                            value=db_guacamole_connections,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRESQL_HOST",
                            value=props.subnet_guacamole_containers_support_ip_addresses[
                                0
                            ],
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRESQL_PASSWORD",
                            secure_value=props.database_password,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRESQL_USERNAME",
                            value=props.database_username,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="REPEAT_INTERVAL",
                            value="180",
                        ),
                    ],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=0.5,
                            memory_in_gb=0.5,
                        ),
                    ),
                ),
            ],
            dns_config=containerinstance.DnsConfigurationArgs(
                name_servers=[props.dns_server_ip],
            ),
            ip_address=containerinstance.IpAddressArgs(
                ports=[
                    containerinstance.PortArgs(
                        port=80,
                        protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                    )
                ],
                type=containerinstance.ContainerGroupIpAddressType.PRIVATE,
            ),
            os_type=containerinstance.OperatingSystemTypes.LINUX,
            resource_group_name=resource_group.name,
            restart_policy=containerinstance.ContainerGroupRestartPolicy.ALWAYS,
            sku=containerinstance.ContainerGroupSku.STANDARD,
            subnet_ids=[
                containerinstance.ContainerGroupSubnetIdArgs(
                    id=props.subnet_guacamole_containers_id
                )
            ],
            volumes=[
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=file_share.name,
                        storage_account_key=props.storage_account_key,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="caddy-etc-caddy",
                ),
            ],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    delete_before_replace=True, replace_on_changes=["containers"]
                ),
            ),
            tags=child_tags,
        )

        # Register outputs
        self.resource_group_name = resource_group.name

        # Register exports
        self.exports = {
            "connection_db_name": db_guacamole_connections,
            "connection_db_server_name": db_server_guacamole.db_server.name,
            "container_group_name": container_group.name,
            "disable_copy": props.disable_copy,
            "disable_paste": props.disable_paste,
            "resource_group_name": resource_group.name,
        }
