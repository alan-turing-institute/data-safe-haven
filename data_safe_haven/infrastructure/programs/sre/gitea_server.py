from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, storage

from data_safe_haven.infrastructure.common import (
    DockerHubCredentials,
    get_ip_address_from_container_group,
)
from data_safe_haven.infrastructure.components import (
    FileShareFile,
    FileShareFileProps,
    LocalDnsRecordComponent,
    LocalDnsRecordProps,
    PostgresqlDatabaseComponent,
    PostgresqlDatabaseProps,
)
from data_safe_haven.resources import resources_path
from data_safe_haven.utility import FileReader


class SREGiteaServerProps:
    """Properties for SREGiteaServerComponent"""

    def __init__(
        self,
        containers_subnet_id: Input[str],
        database_password: Input[str],
        database_subnet_id: Input[str],
        dns_server_ip: Input[str],
        dockerhub_credentials: DockerHubCredentials,
        ldap_server_hostname: Input[str],
        ldap_server_port: Input[int],
        ldap_username_attribute: Input[str],
        ldap_user_filter: Input[str],
        ldap_user_search_base: Input[str],
        location: Input[str],
        resource_group_name: Input[str],
        sre_fqdn: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        database_username: Input[str] | None = None,
    ) -> None:
        self.containers_subnet_id = containers_subnet_id
        self.database_password = database_password
        self.database_subnet_id = database_subnet_id
        self.database_username = (
            database_username if database_username else "postgresadmin"
        )
        self.dns_server_ip = dns_server_ip
        self.dockerhub_credentials = dockerhub_credentials
        self.ldap_server_hostname = ldap_server_hostname
        self.ldap_server_port = ldap_server_port
        self.ldap_username_attribute = ldap_username_attribute
        self.ldap_user_filter = ldap_user_filter
        self.ldap_user_search_base = ldap_user_search_base
        self.location = location
        self.resource_group_name = resource_group_name
        self.sre_fqdn = sre_fqdn
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name


class SREGiteaServerComponent(ComponentResource):
    """Deploy Gitea server with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREGiteaServerProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:GiteaServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "Gitea server"} | (tags if tags else {})

        # Define configuration file shares
        file_share_gitea_caddy = storage.FileShare(
            f"{self._name}_file_share_gitea_caddy",
            access_tier=storage.ShareAccessTier.TRANSACTION_OPTIMIZED,
            account_name=props.storage_account_name,
            resource_group_name=props.resource_group_name,
            share_name="gitea-caddy",
            share_quota=1,
            signed_identifiers=[],
            opts=child_opts,
        )
        file_share_gitea_gitea = storage.FileShare(
            f"{self._name}_file_share_gitea_gitea",
            access_tier=storage.ShareAccessTier.TRANSACTION_OPTIMIZED,
            account_name=props.storage_account_name,
            resource_group_name=props.resource_group_name,
            share_name="gitea-gitea",
            share_quota=1,
            signed_identifiers=[],
            opts=child_opts,
        )

        # Upload caddy file
        caddy_caddyfile_reader = FileReader(
            resources_path / "gitea" / "caddy" / "Caddyfile"
        )
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
            resources_path / "gitea" / "gitea" / "configure.mustache.sh"
        )
        gitea_configure_sh = Output.all(
            admin_email="dshadmin@example.com",
            admin_username="dshadmin",
            ldap_username_attribute=props.ldap_username_attribute,
            ldap_user_filter=props.ldap_user_filter,
            ldap_server_hostname=props.ldap_server_hostname,
            ldap_server_port=props.ldap_server_port,
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
            resources_path / "gitea" / "gitea" / "entrypoint.sh"
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
        db_gitea_repository_name = "gitea"
        db_server_gitea = PostgresqlDatabaseComponent(
            f"{self._name}_db_gitea",
            PostgresqlDatabaseProps(
                database_names=[db_gitea_repository_name],
                database_password=props.database_password,
                database_resource_group_name=props.resource_group_name,
                database_server_name=f"{stack_name}-db-server-gitea",
                database_subnet_id=props.database_subnet_id,
                database_username=props.database_username,
                disable_secure_transport=False,
                location=props.location,
            ),
            opts=child_opts,
            tags=child_tags,
        )

        # Define the container group with guacd, guacamole and caddy
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-group-gitea",
            containers=[
                containerinstance.ContainerArgs(
                    image="caddy:2.8.4",
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
                    image="gitea/gitea:1.22.1",
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
                            value=db_server_gitea.private_ip_address,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__database__NAME", value=db_gitea_repository_name
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__database__USER",
                            value=props.database_username,
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
            dns_config=containerinstance.DnsConfigurationArgs(
                name_servers=[props.dns_server_ip],
            ),
            # Required due to DockerHub rate-limit: https://docs.docker.com/docker-hub/download-rate-limit/
            image_registry_credentials=[
                {
                    "password": Output.secret(props.dockerhub_credentials.access_token),
                    "server": props.dockerhub_credentials.server,
                    "username": props.dockerhub_credentials.username,
                }
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
            location=props.location,
            os_type=containerinstance.OperatingSystemTypes.LINUX,
            resource_group_name=props.resource_group_name,
            restart_policy=containerinstance.ContainerGroupRestartPolicy.ALWAYS,
            sku=containerinstance.ContainerGroupSku.STANDARD,
            subnet_ids=[
                containerinstance.ContainerGroupSubnetIdArgs(
                    id=props.containers_subnet_id
                )
            ],
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
            tags=child_tags,
        )

        # Register the container group in the SRE DNS zone
        local_dns = LocalDnsRecordComponent(
            f"{self._name}_gitea_dns_record_set",
            LocalDnsRecordProps(
                base_fqdn=props.sre_fqdn,
                private_ip_address=get_ip_address_from_container_group(container_group),
                record_name="gitea",
                resource_group_name=props.resource_group_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=container_group)
            ),
        )

        # Register outputs
        self.hostname = local_dns.hostname
