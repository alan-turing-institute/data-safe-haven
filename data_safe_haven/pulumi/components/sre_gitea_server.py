import pathlib

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, dbforpostgresql, network, storage

from data_safe_haven.pulumi.common import (
    get_ip_address_from_container_group,
    get_ip_addresses_from_private_endpoint,
)
from data_safe_haven.pulumi.dynamic.file_share_file import (
    FileShareFile,
    FileShareFileProps,
)
from data_safe_haven.utility import FileReader


class SREGiteaServerProps:
    """Properties for SREGiteaServerComponent"""

    def __init__(
        self,
        database_password: Input[str],
        database_subnet_id: Input[str],
        ldap_bind_dn: Input[str],
        ldap_root_dn: Input[str],
        ldap_search_password: Input[str],
        ldap_server_ip: Input[str],
        ldap_user_search_base: Input[str],
        ldap_user_security_group_name: Input[str],
        location: Input[str],
        networking_resource_group_name: Input[str],
        network_profile_id: Input[str],
        sre_fqdn: Input[str],
        sre_private_dns_zone_id: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
        user_services_resource_group_name: Input[str],
        virtual_network: Input[network.VirtualNetwork],
        virtual_network_resource_group_name: Input[str],
        database_username: Input[str] | None = None,
    ) -> None:
        self.database_password = database_password
        self.database_subnet_id = database_subnet_id
        self.database_username = (
            database_username if database_username else "postgresadmin"
        )
        self.ldap_bind_dn = ldap_bind_dn
        self.ldap_root_dn = ldap_root_dn
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.ldap_user_search_base = ldap_user_search_base
        self.ldap_user_security_group_name = ldap_user_security_group_name
        self.location = location
        self.networking_resource_group_name = networking_resource_group_name
        self.network_profile_id = network_profile_id
        self.sre_fqdn = sre_fqdn
        self.sre_private_dns_zone_id = sre_private_dns_zone_id
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group_name = storage_account_resource_group_name
        self.user_services_resource_group_name = user_services_resource_group_name
        self.virtual_network = virtual_network
        self.virtual_network_resource_group_name = virtual_network_resource_group_name


class SREGiteaServerComponent(ComponentResource):
    """Deploy Gitea server with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREGiteaServerProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:GiteaServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        # Define configuration file shares
        file_share_gitea_caddy = storage.FileShare(
            f"{self._name}_file_share_gitea_caddy",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="gitea-caddy",
            share_quota=1,
            opts=child_opts,
        )
        file_share_gitea_gitea = storage.FileShare(
            f"{self._name}_file_share_gitea_gitea",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="gitea-gitea",
            share_quota=1,
            opts=child_opts,
        )

        # Set resources path
        resources_path = (
            pathlib.Path(__file__).parent.parent.parent / "resources" / "gitea"
        )

        # Upload caddy file
        caddy_caddyfile_reader = FileReader(resources_path / "caddy" / "Caddyfile")
        file_share_gitea_caddy_caddyfile = FileShareFile(
            f"{self._name}_file_share_gitea_caddy_caddyfile",
            FileShareFileProps(
                destination_path=caddy_caddyfile_reader.name,
                share_name=file_share_gitea_caddy.name,
                file_contents=Output.secret(caddy_caddyfile_reader.file_contents()),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=file_share_gitea_caddy)
            ),
        )

        # Upload Gitea configuration script
        gitea_configure_sh_reader = FileReader(
            resources_path / "gitea" / "configure.mustache.sh"
        )
        gitea_configure_sh = Output.all(
            admin_email="dshadmin@example.com",
            admin_username="dshadmin",
            ldap_bind_dn=props.ldap_bind_dn,
            ldap_root_dn=props.ldap_root_dn,
            ldap_search_password=props.ldap_search_password,
            ldap_user_security_group_name=props.ldap_user_security_group_name,
            ldap_server_ip=props.ldap_server_ip,
            ldap_user_search_base=props.ldap_user_search_base,
        ).apply(
            lambda mustache_values: gitea_configure_sh_reader.file_contents(
                mustache_values
            )
        )
        file_share_gitea_gitea_configure_sh = FileShareFile(
            f"{self._name}_file_share_gitea_gitea_configure_sh",
            FileShareFileProps(
                destination_path=gitea_configure_sh_reader.name,
                share_name=file_share_gitea_gitea.name,
                file_contents=Output.secret(gitea_configure_sh),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=file_share_gitea_gitea)
            ),
        )
        # Upload Gitea entrypoint script
        gitea_entrypoint_sh_reader = FileReader(
            resources_path / "gitea" / "entrypoint.sh"
        )
        file_share_gitea_gitea_entrypoint_sh = FileShareFile(
            f"{self._name}_file_share_gitea_gitea_entrypoint_sh",
            FileShareFileProps(
                destination_path=gitea_entrypoint_sh_reader.name,
                share_name=file_share_gitea_gitea.name,
                file_contents=Output.secret(gitea_entrypoint_sh_reader.file_contents()),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=file_share_gitea_gitea)
            ),
        )

        # Define a PostgreSQL server and default database
        gitea_db_server_name = f"{stack_name}-db-gitea"
        gitea_db_server = dbforpostgresql.Server(
            f"{self._name}_gitea_db_server",
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
            resource_group_name=props.user_services_resource_group_name,
            server_name=gitea_db_server_name,
            sku=dbforpostgresql.SkuArgs(
                capacity=2,
                family="Gen5",
                name="GP_Gen5_2",
                tier=dbforpostgresql.SkuTier.GENERAL_PURPOSE,  # required to use private link
            ),
            opts=child_opts,
        )
        gitea_db_database_name = "gitea"
        dbforpostgresql.Database(
            f"{self._name}_gitea_db",
            charset="UTF8",
            database_name=gitea_db_database_name,
            resource_group_name=props.user_services_resource_group_name,
            server_name=gitea_db_server.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=gitea_db_server)
            ),
        )
        # Deploy a private endpoint to the PostgreSQL server
        gitea_db_private_endpoint = network.PrivateEndpoint(
            f"{self._name}_gitea_db_private_endpoint",
            private_endpoint_name=f"{stack_name}-endpoint-gitea-db",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["postgresqlServer"],
                    name=f"{stack_name}-privatelink-gitea-db",
                    private_link_service_connection_state=network.PrivateLinkServiceConnectionStateArgs(
                        actions_required="None",
                        description="Auto-approved",
                        status="Approved",
                    ),
                    private_link_service_id=gitea_db_server.id,
                )
            ],
            resource_group_name=props.user_services_resource_group_name,
            subnet=network.SubnetArgs(id=props.database_subnet_id),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=gitea_db_server)
            ),
        )
        gitea_db_private_ip_address = Output.from_input(
            get_ip_addresses_from_private_endpoint(gitea_db_private_endpoint)
        ).apply(lambda ips: ips[0])

        # Define the container group with guacd, guacamole and caddy
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-group-gitea",
            containers=[
                containerinstance.ContainerArgs(
                    image="caddy:2",
                    name="caddy"[:63],
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=80,
                            protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                        ),
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
                            read_only=True,
                        ),
                    ],
                ),
                containerinstance.ContainerArgs(
                    image="gitea/gitea:1",
                    name="gitea"[:63],
                    command=["/app/custom/entrypoint.sh"],
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="APP_NAME", value="Data Safe Haven Git server"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="RUN_MODE", value="dev"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__database__DB_TYPE", value="postgres"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__database__HOST",
                            value=gitea_db_private_ip_address,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__database__NAME", value=gitea_db_database_name
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__database__USER",
                            value=Output.concat(
                                props.database_username, "@", gitea_db_server_name
                            ),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__database__PASSWD",
                            secure_value=props.database_password,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__database__SSL_MODE", value="require"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__log__LEVEL",
                            # Options are: "Trace", "Debug", "Info" [default], "Warn", "Error", "Critical" or "None".
                            value="Debug",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__security__INSTALL_LOCK", value="true"
                        ),
                    ],
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=22,
                            protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                        ),
                    ],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=2,
                            memory_in_gb=2,
                        ),
                    ),
                    volume_mounts=[
                        containerinstance.VolumeMountArgs(
                            mount_path="/app/custom",
                            name="gitea-app-custom",
                            read_only=True,
                        ),
                    ],
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
                id=props.network_profile_id,
            ),
            os_type=containerinstance.OperatingSystemTypes.LINUX,
            resource_group_name=props.user_services_resource_group_name,
            restart_policy=containerinstance.ContainerGroupRestartPolicy.ALWAYS,
            sku=containerinstance.ContainerGroupSku.STANDARD,
            volumes=[
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=file_share_gitea_caddy.name,
                        storage_account_key=props.storage_account_key,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="caddy-etc-caddy",
                ),
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=file_share_gitea_gitea.name,
                        storage_account_key=props.storage_account_key,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="gitea-app-custom",
                ),
            ],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    delete_before_replace=True,
                    depends_on=[
                        file_share_gitea_caddy_caddyfile,
                        file_share_gitea_gitea_configure_sh,
                        file_share_gitea_gitea_entrypoint_sh,
                    ],
                    replace_on_changes=["containers"],
                ),
            ),
        )
        # Register the container group in the SRE private DNS zone
        private_dns_record_set = network.PrivateRecordSet(
            f"{self._name}_gitea_private_record_set",
            a_records=[
                network.ARecordArgs(
                    ipv4_address=get_ip_address_from_container_group(container_group),
                )
            ],
            private_zone_name=Output.concat("privatelink.", props.sre_fqdn),
            record_type="A",
            relative_record_set_name="gitea",
            resource_group_name=props.networking_resource_group_name,
            ttl=3600,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=container_group)
            ),
        )
        # Redirect the public DNS to private DNS
        network.RecordSet(
            f"{self._name}_gitea_public_record_set",
            cname_record=network.CnameRecordArgs(
                cname=Output.concat("gitea.privatelink.", props.sre_fqdn)
            ),
            record_type="CNAME",
            relative_record_set_name="gitea",
            resource_group_name=props.networking_resource_group_name,
            ttl=3600,
            zone_name=props.sre_fqdn,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=private_dns_record_set)
            ),
        )
