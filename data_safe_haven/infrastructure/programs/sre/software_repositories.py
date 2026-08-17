"""Pulumi component for SRE software repositories"""

from collections.abc import Mapping
from typing import Any

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, network, storage

from data_safe_haven.external import AzureIPv4Range
from data_safe_haven.infrastructure.common import (
    DockerHubCredentials,
    get_ip_address_from_container_group,
)
from data_safe_haven.infrastructure.components import (
    FileShareFile,
    FileShareFileProps,
    LocalDnsRecordComponent,
    LocalDnsRecordProps,
    OperationalInsightsWorkspace,
    PostgresqlDatabaseComponent,
    PostgresqlDatabaseProps,
)
from data_safe_haven.resources import resources_path
from data_safe_haven.types import (
    Ports,
    PostgreSqlExtension,
    SoftwarePackageCategory,
)
from data_safe_haven.utility import FileReader


class SRESoftwareRepositoriesProps:
    """Properties for SRESoftwareRepositoriesComponent"""

    def __init__(
        self,
        database_password: Input[str],
        dns_server_ip: Input[str],
        dockerhub_credentials: DockerHubCredentials,
        location: Input[str],
        log_analytics_workspace: Input[OperationalInsightsWorkspace],
        nexus_admin_password: Input[str],
        resource_group_name: Input[str],
        software_packages: SoftwarePackageCategory,
        sre_fqdn: Input[str],
        nexus_persistent_quota_gb: Input[int],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        subnet_software_repositories_id: Input[str],
        subnet_software_repositories_support: Input[network.Subnet] | None,
        database_username: Input[str] | None = "postgresadmin",
    ) -> None:
        self.database_password = database_password
        self.database_username = (
            database_username if database_username else "postgresadmin"
        )
        self.dns_server_ip = dns_server_ip
        self.dockerhub_credentials = dockerhub_credentials
        self.location = location
        self.log_analytics_workspace = log_analytics_workspace
        self.nexus_admin_password = Output.secret(nexus_admin_password)
        self.nexus_packages: str | None = {
            SoftwarePackageCategory.ANY: "all",
            SoftwarePackageCategory.PRE_APPROVED: "selected",
            SoftwarePackageCategory.NONE: None,
        }[software_packages]
        self.resource_group_name = resource_group_name
        self.nexus_persistent_quota_gb = nexus_persistent_quota_gb
        self.sre_fqdn = sre_fqdn
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.subnet_software_repositories_id = subnet_software_repositories_id
        self.subnet_software_repositories_support = subnet_software_repositories_support


class SRESoftwareRepositoriesComponent(ComponentResource):
    """Deploy SRE update servers with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SRESoftwareRepositoriesProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:SoftwareRepositoriesComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "software repositories"} | (tags if tags else {})

        # Use a dummy hostname if no repositories are deployed
        hostname: Output[str] = "example.com"

        # Define configuration file shares
        file_share_caddy = storage.FileShare(
            f"{self._name}_file_share_caddy",
            access_tier=storage.ShareAccessTier.TRANSACTION_OPTIMIZED,
            account_name=props.storage_account_name,
            resource_group_name=props.resource_group_name,
            share_name="software-repositories-caddy",
            share_quota=1,
            signed_identifiers=[],
            opts=child_opts,
        )
        file_share_nexus = storage.FileShare(
            f"{self._name}_file_share_nexus",
            access_tier=storage.ShareAccessTier.TRANSACTION_OPTIMIZED,
            account_name=props.storage_account_name,
            resource_group_name=props.resource_group_name,
            share_name="software-repositories-nexus",
            share_quota=props.nexus_persistent_quota_gb,
            signed_identifiers=[],
            opts=child_opts,
        )
        file_share_nexus_allowlists = storage.FileShare(
            f"{self._name}_file_share_nexus_allowlists",
            access_tier=storage.ShareAccessTier.TRANSACTION_OPTIMIZED,
            account_name=props.storage_account_name,
            resource_group_name=props.resource_group_name,
            share_name="software-repositories-nexus-allowlists",
            share_quota=1,
            signed_identifiers=[],
            opts=child_opts,
        )

        # Upload Caddyfile
        caddyfile_reader = FileReader(
            resources_path / "software_repositories" / "caddy" / "Caddyfile"
        )
        FileShareFile(
            f"{self._name}_file_share_caddyfile",
            FileShareFileProps(
                destination_path=caddyfile_reader.name,
                share_name=file_share_caddy.name,
                file_contents=Output.secret(caddyfile_reader.file_contents()),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=file_share_caddy)
            ),
        )

        # Upload Nexus allowlists
        cran_allowlist = FileShareFile(
            f"{self._name}_file_share_cran_allowlist",
            FileShareFileProps(
                destination_path="cran.allowlist",
                share_name=file_share_nexus_allowlists.name,
                file_contents="",
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    parent=file_share_nexus_allowlists,
                    ignore_changes=["file_contents"],
                ),
            ),
        )
        pypi_allowlist = FileShareFile(
            f"{self._name}_file_share_pypi_allowlist",
            FileShareFileProps(
                destination_path="pypi.allowlist",
                share_name=file_share_nexus_allowlists.name,
                file_contents="",
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    parent=file_share_nexus_allowlists,
                    ignore_changes=["file_contents"],
                ),
            ),
        )

        self.container_group: containerinstance.ContainerGroup | None = None
        self.exports: dict[str, Any] | None = None

        if (
            props.nexus_packages
            and props.subnet_software_repositories_support is not None
        ):

            # Define the container group with nexus and caddy
            self.dns_record_name = "nexus"
            self.container_group_name = (
                f"{stack_name}-container-group-{self.dns_record_name}"
            )
            self.container_group = containerinstance.ContainerGroup(
                f"{self._name}_container_group",
                container_group_name=self.container_group_name,
                containers=[
                    containerinstance.ContainerArgs(
                        image="caddy:2.11.4",
                        name="caddy"[:63],
                        ports=[
                            containerinstance.ContainerPortArgs(
                                port=80,
                                protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
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
                                read_only=True,
                            ),
                        ],
                    ),
                    containerinstance.ContainerArgs(
                        image="sonatype/nexus3:3.94.1",
                        name="nexus"[:63],
                        environment_variables=[
                            containerinstance.EnvironmentVariableArgs(
                                name="NEXUS_DATASTORE_NEXUS_JDBCURL",
                                value=props.subnet_software_repositories_support.address_prefix.apply(
                                    lambda address_prefix: f"jdbc:postgresql://{self.obtain_first_ip_address(address_prefix)}:5432/nexus?gssEncMode=disable&tcpKeepAlive=true&loginTimeout=5&connectionTimeout=5&socketTimeout=30&cancelSignalTimeout=5&targetServerType=primary",
                                ),
                            ),
                            containerinstance.EnvironmentVariableArgs(
                                name="NEXUS_DATASTORE_NEXUS_USERNAME",
                                value="nexus",
                            ),
                            containerinstance.EnvironmentVariableArgs(
                                name="NEXUS_DATASTORE_NEXUS_PASSWORD",
                                secure_value=props.database_password,
                            ),
                        ],
                        ports=[],
                        resources=containerinstance.ResourceRequirementsArgs(
                            requests=containerinstance.ResourceRequestsArgs(
                                cpu=3,
                                memory_in_gb=4,
                            ),
                        ),
                        volume_mounts=[
                            containerinstance.VolumeMountArgs(
                                mount_path="/nexus-data",
                                name="nexus-nexus-data",
                                read_only=False,
                            ),
                        ],
                    ),
                    containerinstance.ContainerArgs(
                        image="ghcr.io/alan-turing-institute/nexus-allowlist:v0.12.0",
                        name="nexus-allowlist"[:63],
                        environment_variables=[
                            containerinstance.EnvironmentVariableArgs(
                                name="NEXUS_ADMIN_PASSWORD",
                                secure_value=props.nexus_admin_password,
                            ),
                            containerinstance.EnvironmentVariableArgs(
                                name="NEXUS_PACKAGES",
                                value=props.nexus_packages,
                            ),
                            containerinstance.EnvironmentVariableArgs(
                                name="NEXUS_HOST",
                                value="localhost",
                            ),
                            containerinstance.EnvironmentVariableArgs(
                                name="NEXUS_PORT",
                                value=Ports.NEXUS,
                            ),
                            # Use fallback updating method due to issue with changes to
                            # files on Azure storage mount not being recognised by entr
                            containerinstance.EnvironmentVariableArgs(
                                name="ENTR_FALLBACK",
                                value="1",
                            ),
                        ],
                        ports=[],
                        resources=containerinstance.ResourceRequirementsArgs(
                            requests=containerinstance.ResourceRequestsArgs(
                                cpu=0.5,
                                memory_in_gb=0.5,
                            ),
                        ),
                        volume_mounts=[
                            containerinstance.VolumeMountArgs(
                                mount_path="/allowlists",
                                name="nexus-allowlists-allowlists",
                                read_only=True,
                            ),
                            containerinstance.VolumeMountArgs(
                                mount_path="/nexus-data",
                                name="nexus-nexus-data",
                                read_only=True,
                            ),
                        ],
                    ),
                ],
                diagnostics=containerinstance.ContainerGroupDiagnosticsArgs(
                    log_analytics=containerinstance.LogAnalyticsArgs(
                        workspace_id=props.log_analytics_workspace.workspace_id,
                        workspace_key=props.log_analytics_workspace.workspace_key,
                    ),
                ),
                dns_config=containerinstance.DnsConfigurationArgs(
                    name_servers=[props.dns_server_ip],
                ),
                # Required due to DockerHub rate-limit: https://docs.docker.com/docker-hub/download-rate-limit/
                image_registry_credentials=[
                    {
                        "password": Output.secret(
                            props.dockerhub_credentials.access_token
                        ),
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
                        id=props.subnet_software_repositories_id
                    )
                ],
                volumes=[
                    containerinstance.VolumeArgs(
                        azure_file=containerinstance.AzureFileVolumeArgs(
                            share_name=file_share_caddy.name,
                            storage_account_key=props.storage_account_key,
                            storage_account_name=props.storage_account_name,
                        ),
                        name="caddy-etc-caddy",
                    ),
                    containerinstance.VolumeArgs(
                        azure_file=containerinstance.AzureFileVolumeArgs(
                            share_name=file_share_nexus.name,
                            storage_account_key=props.storage_account_key,
                            storage_account_name=props.storage_account_name,
                        ),
                        name="nexus-nexus-data",
                    ),
                    containerinstance.VolumeArgs(
                        azure_file=containerinstance.AzureFileVolumeArgs(
                            share_name=file_share_nexus_allowlists.name,
                            storage_account_key=props.storage_account_key,
                            storage_account_name=props.storage_account_name,
                        ),
                        name="nexus-allowlists-allowlists",
                    ),
                ],
                opts=ResourceOptions.merge(
                    child_opts,
                    ResourceOptions(
                        delete_before_replace=True,
                        replace_on_changes=["containers"],
                        depends_on=[
                            props.log_analytics_workspace.workspace,
                        ],
                    ),
                ),
                tags=child_tags,
            )

            # Define a PostgreSQL server for Nexus
            db_software_repository_name: str = "nexus"
            db_server_software_repositories: PostgresqlDatabaseComponent = (
                PostgresqlDatabaseComponent(
                    f"{self._name}_db_nexus",
                    PostgresqlDatabaseProps(
                        azure_extensions=PostgreSqlExtension.PG_TRGM,  # Extension required by Nexus.
                        database_names=[db_software_repository_name],
                        database_password=props.database_password,
                        database_resource_group_name=props.resource_group_name,
                        database_server_name=f"{stack_name}-db-server-software-repositories",
                        database_subnet_id=props.subnet_software_repositories_support.id,
                        database_username=props.database_username,
                        disable_secure_transport=False,
                        location=props.location,
                    ),
                    opts=ResourceOptions.merge(
                        child_opts,
                        ResourceOptions(replace_with=[self.container_group]),
                    ),
                    tags=child_tags,
                )
            )

            # Register the container group in the SRE DNS zone
            self.local_dns = LocalDnsRecordComponent(
                f"{self._name}_nexus_dns_record_set",
                LocalDnsRecordProps(
                    base_fqdn=props.sre_fqdn,
                    private_ip_address=get_ip_address_from_container_group(
                        self.container_group
                    ),
                    record_name=self.dns_record_name,
                    resource_group_name=props.resource_group_name,
                ),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=self.container_group)
                ),
            )

            hostname = self.local_dns.hostname

            # Register Nexus exports
            self.exports = {
                "connection_db_name": db_software_repository_name,
                "connection_db_server_name": db_server_software_repositories.db_server.name,
                "container_group_name": self.container_group.name,
                "resource_group_name": props.resource_group_name,
            }

        # Register outputs
        self.hostname = hostname
        self.allowlist_file_share_name = file_share_nexus_allowlists.name
        self.allowlist_file_names = {
            "cran": cran_allowlist.destination_path,
            "pypi": pypi_allowlist.destination_path,
        }

    @staticmethod
    def obtain_first_ip_address(address_prefix: str | None) -> str | None:
        if address_prefix:
            return next(
                str(ip) for ip in AzureIPv4Range.from_cidr(address_prefix).available()
            )

        return None
