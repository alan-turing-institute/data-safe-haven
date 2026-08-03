import json
from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, dbforpostgresql, storage
from pulumi_random import RandomPassword

from data_safe_haven.config.config_sections import ConfigSubsectionGiteaMirror
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
)
from data_safe_haven.resources import resources_path
from data_safe_haven.utility import FileReader


class SREGiteaMirrorManagerProps:
    """Properties for SREGiteaMirrorManagerProps"""

    def __init__(
        self,
        db_server_shared: Input[PostgresqlDatabaseComponent],
        db_server_shared_password: Input[str],
        dns_server_ip: Input[str],
        dockerhub_credentials: DockerHubCredentials,
        gitea_workspace_dns_record: str,
        location: Input[str],
        log_analytics_workspace: Input[OperationalInsightsWorkspace],
        mirror_manager_subnet_id: Input[str],
        repository_data: ConfigSubsectionGiteaMirror,
        resource_group_name: Input[str],
        sre_fqdn: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        workspace_username: str,
        workspace_password: Input[str],
    ) -> None:
        self.db_server_shared = db_server_shared
        self.db_server_shared_password = db_server_shared_password
        self.dns_server_ip = dns_server_ip
        self.dockerhub_credentials = dockerhub_credentials
        self.gitea_workspace_dns_record = gitea_workspace_dns_record
        self.location = location
        self.log_analytics_workspace = log_analytics_workspace
        self.mirror_manager_subnet_id = mirror_manager_subnet_id
        self.resource_group_name = resource_group_name
        self.repository_data = repository_data
        self.sre_fqdn = sre_fqdn
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.workspace_username = workspace_username
        self.workspace_password = workspace_password


class SREGiteaMirrorManagerComponent(ComponentResource):
    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREGiteaMirrorManagerProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:GiteaServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "Gitea server"} | (tags if tags else {})

        # Define configuration file shares

        file_share_gitea_mirror_data = storage.FileShare(
            f"{self._name}_file_share_gitea_mirror_data",
            access_tier=storage.ShareAccessTier.TRANSACTION_OPTIMIZED,
            account_name=props.storage_account_name,
            resource_group_name=props.resource_group_name,
            share_name="gitea-mirror-data",
            share_quota=2,
            signed_identifiers=[],
            opts=child_opts,
        )

        file_share_gitea_mirror_app_custom = storage.FileShare(
            f"{self._name}_file_share_gitea_app_custom",
            access_tier=storage.ShareAccessTier.TRANSACTION_OPTIMIZED,
            account_name=props.storage_account_name,
            resource_group_name=props.resource_group_name,
            share_name="gitea-mirror-app-custom",
            share_quota=1,
            signed_identifiers=[],
            opts=child_opts,
        )

        # Upload Gitea configuration script
        gitea_configure_sh_reader = FileReader(
            resources_path / "gitea" / "gitea-mirror" / "configure.mustache.sh"
        )

        gitea_mirror_user_password: RandomPassword = RandomPassword(
            f"{self._name}_password_gitea_mirror_user",
            length=20,
            special=False,
        )

        mirror_username: str = "mirroruser"
        mirror_password: Output[str] = gitea_mirror_user_password.result

        gitea_configure_sh = Output.all(
            admin_email="dshadmin@example.com",
            admin_username="dshadmin",
            mirror_email="mirror@example.com",
            mirror_username=mirror_username,
        ).apply(gitea_configure_sh_reader.file_contents)

        file_share_gitea_gitea_configure_sh = FileShareFile(
            f"{self._name}_file_share_gitea_gitea_configure_sh",
            FileShareFileProps(
                destination_path=gitea_configure_sh_reader.name,
                share_name=file_share_gitea_mirror_app_custom.name,
                file_contents=Output.secret(gitea_configure_sh),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=file_share_gitea_mirror_app_custom)
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
                share_name=file_share_gitea_mirror_app_custom.name,
                file_contents=Output.secret(gitea_entrypoint_sh_reader.file_contents()),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=file_share_gitea_mirror_app_custom)
            ),
        )

        # Add a database to the shared PostgreSQL server
        db_gitea_repository_name = "giteamirror"
        db_gitea_repository = dbforpostgresql.Database(
            f"{self._name}_db_{db_gitea_repository_name}",
            charset="UTF8",
            database_name=db_gitea_repository_name,
            resource_group_name=props.db_server_shared.database_resource_group_name,
            server_name=props.db_server_shared.db_server.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=props.db_server_shared)
            ),
        )

        # Define the container group.
        self.container_group_name = f"{stack_name}-container-group-mirror-manager"
        self.dns_record_name = "giteamirror"
        self.gitea_default_port: int = 3000

        self.container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=self.container_group_name,
            containers=[
                containerinstance.ContainerArgs(
                    image="ghcr.io/alan-turing-institute/gitea-mirror-manager:v0.0.1",
                    name="mirrormanager",
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="MIRROR_SERVER_URL",
                            value=Output.concat(
                                f"http://{self.dns_record_name}.",
                                props.sre_fqdn,
                                f":{self.gitea_default_port}",
                            ),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="MIRROR_SERVER_USERNAME", value=mirror_username
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="MIRROR_SERVER_PASSWORD",
                            secure_value=mirror_password,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="WORKSPACE_SERVER_URL",
                            value=Output.concat(
                                f"http://{props.gitea_workspace_dns_record}.",
                                props.sre_fqdn,
                            ),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="WORKSPACE_SERVER_USERNAME",
                            value=props.workspace_username,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="WORKSPACE_SERVER_PASSWORD",
                            secure_value=props.workspace_password,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="REPOSITORY_DATA",
                            secure_value=json.dumps(
                                props.repository_data.model_dump(mode="json")
                            ),
                        ),
                    ],
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
                ),
                containerinstance.ContainerArgs(
                    image="gitea/gitea:1.27.1",
                    name="gitea"[:63],
                    command=["/app/custom/entrypoint.sh"],
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="APP_NAME", value="Data Safe Haven Git Mirror server"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="RUN_MODE", value="dev"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__database__DB_TYPE", value="postgres"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__database__HOST",
                            value=props.db_server_shared.private_ip_address,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__database__NAME", value=db_gitea_repository_name
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__database__USER",
                            value=props.db_server_shared.db_server.administrator_login,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__database__PASSWD",
                            secure_value=props.db_server_shared_password,
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
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__server__DOMAIN",
                            value=Output.concat(
                                f"{self.dns_record_name}.",
                                props.sre_fqdn,
                            ),
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__migrations__ALLOW_LOCALNETWORKS", value="true"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="MIRROR_SERVER_PASSWORD",
                            secure_value=mirror_password,
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
                            name="gitea-mirror-app-custom",
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
            restart_policy=containerinstance.ContainerGroupRestartPolicy.ON_FAILURE,
            sku=containerinstance.ContainerGroupSku.STANDARD,
            subnet_ids=[
                containerinstance.ContainerGroupSubnetIdArgs(
                    id=props.mirror_manager_subnet_id
                )
            ],
            volumes=[
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=file_share_gitea_mirror_data.name,
                        storage_account_key=props.storage_account_key,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="gitea-mirror-data",
                ),
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=file_share_gitea_mirror_app_custom.name,
                        storage_account_key=props.storage_account_key,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="gitea-mirror-app-custom",
                ),
            ],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    delete_before_replace=True,
                    depends_on=[
                        db_gitea_repository,
                        file_share_gitea_gitea_entrypoint_sh,
                        file_share_gitea_gitea_configure_sh,
                        props.log_analytics_workspace.workspace,
                    ],
                    replace_on_changes=["containers"],
                ),
            ),
            tags=child_tags,
        )

        self.local_dns = LocalDnsRecordComponent(
            f"{self._name}_giteamirror_dns_record_set",
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
