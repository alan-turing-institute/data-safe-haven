"""Pulumi component for SRE remote desktop"""
import pathlib

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import (
    containerinstance,
    dbforpostgresql,
    network,
    resources,
    storage,
)

from data_safe_haven.external import AzureIPv4Range
from data_safe_haven.pulumi.common import (
    get_id_from_subnet,
    get_ip_address_from_container_group,
)
from data_safe_haven.pulumi.dynamic.azuread_application import (
    AzureADApplication,
    AzureADApplicationProps,
)
from data_safe_haven.pulumi.dynamic.file_share_file import (
    FileShareFile,
    FileShareFileProps,
)
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
        ldap_bind_dn: Input[str],
        ldap_group_search_base: Input[str],
        ldap_search_password: Input[str],
        ldap_server_ip: Input[str],
        ldap_user_search_base: Input[str],
        ldap_user_security_group_name: Input[str],
        location: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
        subnet_guacamole_containers: Input[network.GetSubnetResult],
        subnet_guacamole_containers_support: Input[network.GetSubnetResult],
        virtual_network: Input[network.VirtualNetwork],
        virtual_network_resource_group_name: Input[str],
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
        self.ldap_bind_dn = ldap_bind_dn
        self.ldap_group_search_base = ldap_group_search_base
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.ldap_user_search_base = ldap_user_search_base
        self.ldap_user_security_group_name = ldap_user_security_group_name
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
        self.subnet_guacamole_containers_support_id = Output.from_input(
            subnet_guacamole_containers_support
        ).apply(get_id_from_subnet)
        self.subnet_guacamole_containers_support_ip_addresses = Output.from_input(
            subnet_guacamole_containers_support
        ).apply(
            lambda s: [
                str(ip) for ip in AzureIPv4Range.from_cidr(s.address_prefix).available()
            ]
            if s.address_prefix
            else []
        )
        self.virtual_network = virtual_network
        self.virtual_network_resource_group_name = virtual_network_resource_group_name


class SRERemoteDesktopComponent(ComponentResource):
    """Deploy remote desktop gateway with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SRERemoteDesktopProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:RemoteDesktopComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

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
            share_quota=1,
            opts=child_opts,
        )

        # Upload Caddyfile
        resources_path = pathlib.Path(__file__).parent.parent.parent / "resources"
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
        db_server_guacamole_name = f"{stack_name}-db-server-guacamole"
        db_server_guacamole = dbforpostgresql.Server(
            f"{self._name}_db_server_guacamole",
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
            resource_group_name=resource_group.name,
            server_name=db_server_guacamole_name,
            sku=dbforpostgresql.SkuArgs(
                capacity=2,
                family="Gen5",
                name="GP_Gen5_2",
                tier=dbforpostgresql.SkuTier.GENERAL_PURPOSE,  # required to use private link
            ),
            opts=child_opts,
        )
        network.PrivateEndpoint(
            f"{self._name}_db_server_guacamole_private_endpoint",
            custom_dns_configs=[
                network.CustomDnsConfigPropertiesFormatArgs(
                    ip_addresses=[
                        props.subnet_guacamole_containers_support_ip_addresses[0]
                    ],
                )
            ],
            private_endpoint_name=f"{stack_name}-endpoint-db-server-guacamole",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["postgresqlServer"],
                    name=f"{stack_name}-privatelink-db-server-guacamole",
                    private_link_service_connection_state=network.PrivateLinkServiceConnectionStateArgs(
                        actions_required="None",
                        description="Auto-approved",
                        status="Approved",
                    ),
                    private_link_service_id=db_server_guacamole.id,
                )
            ],
            resource_group_name=resource_group.name,
            subnet=network.SubnetArgs(id=props.subnet_guacamole_containers_support_id),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=db_server_guacamole)
            ),
        )
        connection_db_name = "guacamole"
        connection_db = dbforpostgresql.Database(
            f"{self._name}_connection_db",
            charset="UTF8",
            database_name=connection_db_name,
            resource_group_name=resource_group.name,
            server_name=db_server_guacamole.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=db_server_guacamole)
            ),
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
                child_opts,
                ResourceOptions(
                    depends_on=[props.virtual_network],
                    ignore_changes=[
                        "container_network_interface_configurations"
                    ],  # allow container groups to be registered to this interface
                ),
            ),
        )

        # Define the container group with guacd, guacamole and caddy
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group_remote_desktop",
            container_group_name=f"{stack_name}-container-group-remote-desktop",
            containers=[
                containerinstance.ContainerArgs(
                    image="caddy:2.7.2",
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
                    image="guacamole/guacamole:1.5.3",
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
                            name="POSTGRES_DATABASE", value=connection_db_name
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_HOSTNAME",
                            value=props.subnet_guacamole_containers_support_ip_addresses[
                                0
                            ],
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
                            value=f"{props.database_username}@{db_server_guacamole_name}",
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
                    image="guacamole/guacd:1.5.3",
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
                    image="ghcr.io/alan-turing-institute/guacamole-user-sync:v0.1.0",
                    name="guacamole-user-sync"[:63],
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_BIND_DN",
                            value=props.ldap_bind_dn,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_BIND_PASSWORD",
                            secure_value=props.ldap_search_password,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_GROUP_BASE_DN",
                            value=props.ldap_group_search_base,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_GROUP_FILTER",
                            value=Output.concat("(objectClass=group)"),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_HOST",
                            value=props.ldap_server_ip,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_USER_BASE_DN",
                            value=props.ldap_user_search_base,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="LDAP_USER_FILTER",
                            value=Output.concat(
                                "(&(objectClass=user)(memberOf=CN=",
                                props.ldap_user_security_group_name,
                                ",",
                                props.ldap_group_search_base,
                                "))",
                            ),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_DB_NAME",
                            value=connection_db_name,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_HOST",
                            value=props.subnet_guacamole_containers_support_ip_addresses[
                                0
                            ],
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_PASSWORD",
                            secure_value=props.database_password,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="POSTGRES_USERNAME",
                            value=f"{props.database_username}@{db_server_guacamole_name}",
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
            ip_address=containerinstance.IpAddressArgs(
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
                    name="caddy-etc-caddy",
                ),
            ],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    delete_before_replace=True, replace_on_changes=["containers"]
                ),
            ),
        )

        # Register outputs
        self.resource_group_name = resource_group.name

        # Register exports
        self.exports = {
            "connection_db_name": connection_db.name,
            "connection_db_server_name": db_server_guacamole_name,
            "container_group_name": container_group.name,
            "container_ip_address": get_ip_address_from_container_group(
                container_group
            ),
            "disable_copy": props.disable_copy,
            "disable_paste": props.disable_paste,
            "resource_group_name": resource_group.name,
        }
