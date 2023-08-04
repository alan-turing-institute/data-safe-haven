import pathlib

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, dbforpostgresql, network, storage

from data_safe_haven.functions import b64encode
from data_safe_haven.pulumi.common import (
    get_ip_address_from_container_group,
    get_ip_addresses_from_private_endpoint,
)
from data_safe_haven.pulumi.dynamic.file_share_file import (
    FileShareFile,
    FileShareFileProps,
)
from data_safe_haven.utility import FileReader


class SREHedgeDocServerProps:
    """Properties for SREHedgeDocServerComponent"""

    def __init__(
        self,
        database_password: Input[str],
        database_subnet_id: Input[str],
        domain_netbios_name: Input[str],
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
        self.database_subnet_id = database_subnet_id
        self.database_password = database_password
        self.database_username = (
            database_username if database_username else "postgresadmin"
        )
        self.domain_netbios_name = domain_netbios_name
        self.ldap_bind_dn = ldap_bind_dn
        self.ldap_root_dn = ldap_root_dn
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.ldap_user_search_base = ldap_user_search_base
        self.ldap_user_security_group_cn = Output.all(
            group_name=ldap_user_security_group_name, root_dn=ldap_root_dn
        ).apply(
            lambda kwargs: ",".join(
                (
                    kwargs["group_name"],
                    "OU=Data Safe Haven Security Groups",
                    kwargs["root_dn"],
                )
            )
        )
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


class SREHedgeDocServerComponent(ComponentResource):
    """Deploy HedgeDoc server with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREHedgeDocServerProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:HedgeDocServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        # Define configuration file shares
        file_share_hedgedoc_caddy = storage.FileShare(
            f"{self._name}_file_share_hedgedoc_caddy",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="hedgedoc-caddy",
            share_quota=1,
            opts=child_opts,
        )

        # Set resources path
        resources_path = (
            pathlib.Path(__file__).parent.parent.parent / "resources" / "hedgedoc"
        )

        # Upload caddy file
        caddy_caddyfile_reader = FileReader(resources_path / "caddy" / "Caddyfile")
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
            resources_path / "hedgedoc" / "config.json"
        )

        # Define a PostgreSQL server and default database
        db_server_hedgedoc_name = f"{stack_name}-db-server-hedgedoc"
        db_server_hedgedoc = dbforpostgresql.Server(
            f"{self._name}_db_server_hedgedoc",
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
            server_name=db_server_hedgedoc_name,
            sku=dbforpostgresql.SkuArgs(
                capacity=2,
                family="Gen5",
                name="GP_Gen5_2",
                tier=dbforpostgresql.SkuTier.GENERAL_PURPOSE,  # required to use private link
            ),
            opts=child_opts,
        )
        db_hedgedoc_documents_name = "hedgedoc"
        dbforpostgresql.Database(
            f"{self._name}_db_hedgedoc_documents",
            charset="UTF8",
            database_name=db_hedgedoc_documents_name,
            resource_group_name=props.user_services_resource_group_name,
            server_name=db_server_hedgedoc.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=db_server_hedgedoc)
            ),
        )
        # Deploy a private endpoint to the PostgreSQL server
        db_server_hedgedoc_private_endpoint = network.PrivateEndpoint(
            f"{self._name}_db_server_hedgedoc_private_endpoint",
            private_endpoint_name=f"{stack_name}-endpoint-db-server-hedgedoc",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["postgresqlServer"],
                    name=f"{stack_name}-privatelink-db-server-hedgedoc",
                    private_link_service_connection_state=network.PrivateLinkServiceConnectionStateArgs(
                        actions_required="None",
                        description="Auto-approved",
                        status="Approved",
                    ),
                    private_link_service_id=db_server_hedgedoc.id,
                )
            ],
            resource_group_name=props.user_services_resource_group_name,
            subnet=network.SubnetArgs(id=props.database_subnet_id),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=db_server_hedgedoc)
            ),
        )
        hedgedoc_db_private_ip_address = get_ip_addresses_from_private_endpoint(
            db_server_hedgedoc_private_endpoint
        ).apply(lambda ips: ips[0])

        # Define the container group with guacd, guacamole and caddy
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-group-hedgedoc",
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
                    image="quay.io/hedgedoc/hedgedoc:1.9.8",
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
                            value=hedgedoc_db_private_ip_address,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_DB_PASSWORD",
                            secure_value=props.database_password,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_DB_PORT",
                            value="5432",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_DB_USERNAME",
                            value=Output.concat(
                                props.database_username, "@", db_server_hedgedoc_name
                            ),
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
                            name="CMD_LDAP_BINDCREDENTIALS",
                            secure_value=props.ldap_search_password,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_LDAP_BINDDN",
                            value=props.ldap_bind_dn,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_LDAP_PROVIDERNAME",
                            value=props.domain_netbios_name,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_LDAP_SEARCHBASE",
                            value=props.ldap_user_search_base,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_LDAP_SEARCHFILTER",
                            value=(
                                "(&"
                                "(objectClass=user)"
                                f"(memberOf=CN={props.ldap_user_security_group_cn})"
                                f"(sAMAccountName={{{{username}}}})"
                                ")"
                            ),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_LDAP_URL",
                            value=f"ldap://{props.ldap_server_ip}",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_LDAP_USERIDFIELD",
                            value="sAMAccountName",
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
        )
        # Register the container group in the SRE private DNS zone
        private_dns_record_set = network.PrivateRecordSet(
            f"{self._name}_hedgedoc_private_record_set",
            a_records=[
                network.ARecordArgs(
                    ipv4_address=get_ip_address_from_container_group(container_group),
                )
            ],
            private_zone_name=Output.concat("privatelink.", props.sre_fqdn),
            record_type="A",
            relative_record_set_name="hedgedoc",
            resource_group_name=props.networking_resource_group_name,
            ttl=3600,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=container_group)
            ),
        )
        # Redirect the public DNS to private DNS
        network.RecordSet(
            f"{self._name}_hedgedoc_public_record_set",
            cname_record=network.CnameRecordArgs(
                cname=Output.concat("hedgedoc.privatelink.", props.sre_fqdn)
            ),
            record_type="CNAME",
            relative_record_set_name="hedgedoc",
            resource_group_name=props.networking_resource_group_name,
            ttl=3600,
            zone_name=props.sre_fqdn,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=private_dns_record_set)
            ),
        )
