from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, storage

from data_safe_haven.functions import b64encode
from data_safe_haven.infrastructure.common import (
    Ports,
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


class SREHedgeDocServerProps:
    """Properties for SREHedgeDocServerComponent"""

    def __init__(
        self,
        containers_subnet_id: Input[str],
        database_password: Input[str],
        database_subnet_id: Input[str],
        dns_resource_group_name: Input[str],
        dns_server_ip: Input[str],
        ldap_server_hostname: Input[str],
        ldap_server_port: Input[int],
        ldap_user_filter: Input[str],
        ldap_user_search_base: Input[str],
        ldap_username_attribute: Input[str],
        location: Input[str],
        networking_resource_group_name: Input[str],
        sre_fqdn: Input[str],
        sre_private_dns_zone_id: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
        user_services_resource_group_name: Input[str],
        database_username: Input[str] | None = None,
    ) -> None:
        self.containers_subnet_id = containers_subnet_id
        self.database_subnet_id = database_subnet_id
        self.database_password = database_password
        self.database_username = (
            database_username if database_username else "postgresadmin"
        )
        self.dns_resource_group_name = dns_resource_group_name
        self.dns_server_ip = dns_server_ip
        self.ldap_server_hostname = ldap_server_hostname
        self.ldap_server_port = Output.from_input(ldap_server_port).apply(str)
        self.ldap_user_filter = ldap_user_filter
        self.ldap_user_search_base = ldap_user_search_base
        self.ldap_username_attribute = ldap_username_attribute
        self.location = location
        self.networking_resource_group_name = networking_resource_group_name
        self.sre_fqdn = sre_fqdn
        self.sre_private_dns_zone_id = sre_private_dns_zone_id
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group_name = storage_account_resource_group_name
        self.user_services_resource_group_name = user_services_resource_group_name


class SREHedgeDocServerComponent(ComponentResource):
    """Deploy HedgeDoc server with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREHedgeDocServerProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:HedgeDocServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Define configuration file shares
        file_share_hedgedoc_caddy = storage.FileShare(
            f"{self._name}_file_share_hedgedoc_caddy",
            access_tier=storage.ShareAccessTier.COOL,
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="hedgedoc-caddy",
            share_quota=1,
            signed_identifiers=[],
            opts=child_opts,
        )

        # Upload caddy file
        caddy_caddyfile_reader = FileReader(
            resources_path / "hedgedoc" / "caddy" / "Caddyfile"
        )
        file_share_hedgedoc_caddy_caddyfile = FileShareFile(
            f"{self._name}_file_share_hedgedoc_caddy_caddyfile",
            FileShareFileProps(
                destination_path=caddy_caddyfile_reader.name,
                share_name=file_share_hedgedoc_caddy.name,
                file_contents=Output.secret(caddy_caddyfile_reader.file_contents()),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=file_share_hedgedoc_caddy)
            ),
        )

        # Load HedgeDoc configuration file for later use
        hedgedoc_config_json_reader = FileReader(
            resources_path / "hedgedoc" / "hedgedoc" / "config.json"
        )

        # Define a PostgreSQL server and default database
        db_hedgedoc_documents_name = "hedgedoc"
        db_server_hedgedoc = PostgresqlDatabaseComponent(
            f"{self._name}_db_hedgedoc",
            PostgresqlDatabaseProps(
                database_names=[db_hedgedoc_documents_name],
                database_password=props.database_password,
                database_resource_group_name=props.user_services_resource_group_name,
                database_server_name=f"{stack_name}-db-server-hedgedoc",
                database_subnet_id=props.database_subnet_id,
                database_username=props.database_username,
                location=props.location,
            ),
            opts=child_opts,
            tags=child_tags,
        )

        # Define the container group with guacd, guacamole and caddy
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-group-hedgedoc",
            containers=[
                containerinstance.ContainerArgs(
                    image="caddy:2.7.6",
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
                    image="quay.io/hedgedoc/hedgedoc:1.9.9",
                    name="hedgedoc"[:63],
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_ALLOW_ANONYMOUS",
                            value="false",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_DB_DATABASE",
                            value=db_hedgedoc_documents_name,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_DB_DIALECT",
                            value="postgres",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_DB_HOST",
                            value=db_server_hedgedoc.private_ip_address,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_DB_PASSWORD",
                            secure_value=props.database_password,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_DB_PORT",
                            value=Ports.POSTGRESQL,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_DB_USERNAME",
                            value=props.database_username,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_DOMAIN",
                            value=Output.concat("hedgedoc.", props.sre_fqdn),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_EMAIL",
                            value="false",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_LDAP_PROVIDERNAME",
                            value="Data Safe Haven",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_LDAP_SEARCHBASE",
                            value=props.ldap_user_search_base,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_LDAP_SEARCHFILTER",
                            value=Output.concat(
                                "(&",
                                props.ldap_user_filter,
                                "(",
                                props.ldap_username_attribute,
                                "={{username}})",
                                ")",
                            ),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_LDAP_URL",
                            value=Output.concat(
                                "ldap://",
                                props.ldap_server_hostname,
                                ":",
                                props.ldap_server_port,
                            ),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_LDAP_USERIDFIELD",
                            value=props.ldap_username_attribute,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_LOGLEVEL",
                            value="info",
                        ),
                    ],
                    ports=[],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=2,
                            memory_in_gb=2,
                        ),
                    ),
                    volume_mounts=[
                        containerinstance.VolumeMountArgs(
                            mount_path="/files",
                            name="hedgedoc-files-config-json",
                            read_only=True,
                        ),
                    ],
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
            resource_group_name=props.user_services_resource_group_name,
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
                        share_name=file_share_hedgedoc_caddy.name,
                        storage_account_key=props.storage_account_key,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="caddy-etc-caddy",
                ),
                containerinstance.VolumeArgs(
                    name="hedgedoc-files-config-json",
                    secret={
                        "config.json": b64encode(
                            hedgedoc_config_json_reader.file_contents()
                        )
                    },
                ),
            ],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    delete_before_replace=True,
                    depends_on=[
                        file_share_hedgedoc_caddy_caddyfile,
                    ],
                    replace_on_changes=["containers"],
                ),
            ),
            tags=child_tags,
        )

        # Register the container group in the SRE DNS zone
        LocalDnsRecordComponent(
            f"{self._name}_hedgedoc_dns_record_set",
            LocalDnsRecordProps(
                base_fqdn=props.sre_fqdn,
                public_dns_resource_group_name=props.networking_resource_group_name,
                private_dns_resource_group_name=props.dns_resource_group_name,
                private_ip_address=get_ip_address_from_container_group(container_group),
                record_name="hedgedoc",
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=container_group)
            ),
        )
