# Standard library imports
import pathlib
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, dbforpostgresql, network, storage

# Local imports
from data_safe_haven.helpers import (
    b64encode,
    FileReader,
)
from ..common.transformations import get_ip_addresses_from_private_endpoint
from ..dynamic.file_share_file import FileShareFile, FileShareFileProps


class SREHedgeDocServerProps:
    """Properties for SREHedgeDocServerComponent"""

    def __init__(
        self,
        container_ip_address: Input[str],
        database_password: Input[str],
        database_subnet_id: Input[str],
        ldap_root_dn: Input[str],
        ldap_search_password: Input[str],
        ldap_server_ip: Input[str],
        ldap_security_group_name: Input[str],
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
        database_username: Optional[Input[str]] = None,
    ):
        self.container_ip_address = container_ip_address
        self.database_subnet_id = database_subnet_id
        self.database_password = database_password
        self.database_username = (
            database_username if database_username else "postgresadmin"
        )
        self.ldap_root_dn = ldap_root_dn
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.ldap_security_group_name = ldap_security_group_name
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
    """Deploy secure research desktops with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SREHedgeDocServerProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:sre:HedgeDocServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

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
            opts=child_opts,
        )

        # Load HedgeDoc configuration file for later use
        hedgedoc_config_json_reader = FileReader(
            resources_path / "hedgedoc" / "config.json"
        )

        # Define a PostgreSQL server and default database
        hedgedoc_db_server_name = f"{stack_name}-db-hedgedoc"
        hedgedoc_db_server = dbforpostgresql.Server(
            f"{self._name}_hedgedoc_db_server",
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
            resource_group_name=props.user_services_resource_group_name,
            server_name=hedgedoc_db_server_name,
            sku=dbforpostgresql.SkuArgs(
                capacity=2,
                family="Gen5",
                name="GP_Gen5_2",
                tier=dbforpostgresql.SkuTier.GENERAL_PURPOSE,  # required to use private link
            ),
            opts=child_opts,
        )
        hedgedoc_db_database_name = "hedgedoc"
        hedgedoc_db = dbforpostgresql.Database(
            f"{self._name}_hedgedoc_db",
            charset="UTF8",
            database_name=hedgedoc_db_database_name,
            resource_group_name=props.user_services_resource_group_name,
            server_name=hedgedoc_db_server.name,
            opts=ResourceOptions(parent=hedgedoc_db_server),
        )
        # Deploy a private endpoint to the PostgreSQL server
        hedgedoc_db_private_endpoint = network.PrivateEndpoint(
            f"{self._name}_hedgedoc_db_private_endpoint",
            private_endpoint_name=f"{stack_name}-endpoint-hedgedoc-db",
            private_link_service_connections=[
                network.PrivateLinkServiceConnectionArgs(
                    group_ids=["postgresqlServer"],
                    name=f"{stack_name}-privatelink-hedgedoc-db",
                    private_link_service_connection_state=network.PrivateLinkServiceConnectionStateArgs(
                        actions_required="None",
                        description="Auto-approved",
                        status="Approved",
                    ),
                    private_link_service_id=hedgedoc_db_server.id,
                )
            ],
            resource_group_name=props.user_services_resource_group_name,
            subnet=network.SubnetArgs(id=props.database_subnet_id),
            opts=child_opts,
        )
        hedgedoc_db_private_ip_address = Output.from_input(
            get_ip_addresses_from_private_endpoint(hedgedoc_db_private_endpoint)
        ).apply(lambda ips: ips[0])

        # Define the container group with guacd, guacamole and caddy
        container_group_hedgedoc = containerinstance.ContainerGroup(
            f"{self._name}_container_group_hedgedoc",
            container_group_name=f"{stack_name}-container-group-hedgedoc",
            containers=[
                containerinstance.ContainerArgs(
                    image="caddy:latest",
                    name=f"{stack_name[:35]}-container-group-hedgedoc-caddy",  # maximum of 63 characters
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
                    image="quay.io/hedgedoc/hedgedoc:latest",
                    name=f"{stack_name[:29]}-container-group-hedgedoc-hedgedoc",  # maximum of 63 characters
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_DB_DATABASE",
                            value=hedgedoc_db_database_name,
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
                                props.database_username, "@", hedgedoc_db_server_name
                            ),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_DOMAIN",
                            value=Output.concat("hedgedoc.", props.sre_fqdn),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CMD_LOGLEVEL",
                            value="debug",
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
                ip=props.container_ip_address,
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
                ResourceOptions(
                    depends_on=[
                        file_share_hedgedoc_caddy_caddyfile,
                    ]
                ),
                child_opts,
            ),
        )

        # Register this in the SRE private DNS zone
        hedgedoc_private_record_set = network.PrivateRecordSet(
            f"{self._name}_hedgedoc_private_record_set",
            a_records=[
                network.ARecordArgs(
                    ipv4_address=props.container_ip_address,
                )
            ],
            private_zone_name=Output.concat("privatelink.", props.sre_fqdn),
            record_type="A",
            relative_record_set_name="hedgedoc",
            resource_group_name=props.networking_resource_group_name,
            ttl=3600,
            opts=child_opts,
        )
        # Redirect the public DNS to private DNS
        hedgedoc_public_record_set = network.RecordSet(
            f"{self._name}_hedgedoc_public_record_set",
            cname_record=network.CnameRecordArgs(
                cname=Output.concat("hedgedoc.privatelink.", props.sre_fqdn)
            ),
            record_type="CNAME",
            relative_record_set_name="hedgedoc",
            resource_group_name=props.networking_resource_group_name,
            ttl=3600,
            zone_name=props.sre_fqdn,
            opts=child_opts,
        )
