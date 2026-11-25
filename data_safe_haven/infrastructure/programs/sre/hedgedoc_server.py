from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import (
    app,
    dbforpostgresql,
)

from data_safe_haven.config import LOGGING_LEVELS
from data_safe_haven.functions import b64encode
from data_safe_haven.infrastructure.common import (
    DockerHubCredentials,
)
from data_safe_haven.infrastructure.components import (
    LocalDnsRecordComponent,
    LocalDnsRecordProps,
    OperationalInsightsWorkspace,
    PostgresqlDatabaseComponent,
)
from data_safe_haven.resources import resources_path
from data_safe_haven.types import Ports
from data_safe_haven.utility import FileReader, LogLevelParser


class SREHedgeDocServerProps:
    """Properties for SREHedgeDocServerComponent"""

    @staticmethod
    def log_level_convert(log_level: str) -> str:
        if log_level in LOGGING_LEVELS.keys():
            # Cap the level to at most "debug"
            return "debug" if log_level == "trace" else log_level
        else:
            # The key doesn't exist
            msg = f"Logging level must be one of {', '.join(LOGGING_LEVELS)}."
            raise ValueError(msg)

    def __init__(
        self,
        containers_subnet_id: Input[str],
        db_server_shared: Input[PostgresqlDatabaseComponent],
        db_server_shared_password: Input[str],
        dns_server_ip: Input[str],
        dockerhub_credentials: DockerHubCredentials,
        ldap_server_hostname: Input[str],
        ldap_server_port: Input[int],
        ldap_user_filter: Input[str],
        ldap_user_search_base: Input[str],
        ldap_username_attribute: Input[str],
        location: Input[str],
        log_analytics_workspace: Input[OperationalInsightsWorkspace],
        resource_group_name: Input[str],
        sre_fqdn: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        log_level: Input[str],
    ) -> None:
        self.containers_subnet_id = containers_subnet_id
        self.db_server_shared = db_server_shared
        self.db_server_shared_password = db_server_shared_password
        self.resource_group_name = resource_group_name
        self.dns_server_ip = dns_server_ip
        self.dockerhub_credentials = dockerhub_credentials
        self.ldap_server_hostname = ldap_server_hostname
        self.ldap_server_port = Output.from_input(ldap_server_port).apply(str)
        self.ldap_user_filter = ldap_user_filter
        self.ldap_user_search_base = ldap_user_search_base
        self.ldap_username_attribute = ldap_username_attribute
        self.location = location
        self.log_analytics_workspace = log_analytics_workspace
        self.resource_group_name = resource_group_name
        self.sre_fqdn = sre_fqdn
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.log_level = log_level


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
        child_tags = {"component": "HedgeDoc server"} | (tags if tags else {})

        # Load HedgeDoc configuration file for later use
        hedgedoc_config_json_reader = FileReader(
            resources_path / "hedgedoc" / "hedgedoc" / "config.json"
        )

        # Add a database to the shared PostgreSQL server
        db_hedgedoc_documents_name = "hedgedoc"
        db_hedgedoc_documents = dbforpostgresql.Database(
            f"{self._name}_db_hedgedoc",
            charset="UTF8",
            database_name=db_hedgedoc_documents_name,
            resource_group_name=props.db_server_shared.database_resource_group_name,
            server_name=props.db_server_shared.db_server.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=props.db_server_shared)
            ),
        )

        # Set up the managed environment
        self.managed_env = app.ManagedEnvironment(
            f"{self._name}_managed_env",
            resource_group_name=props.resource_group_name,
            app_logs_configuration=app.AppLogsConfigurationArgs(
                destination="log-analytics",
                log_analytics_configuration=app.LogAnalyticsConfigurationArgs(
                    customer_id=props.log_analytics_workspace.workspace_id,
                    shared_key=props.log_analytics_workspace.workspace_key,
                ),
            ),
            vnet_configuration=app.VnetConfigurationArgs(
                infrastructure_subnet_id=props.containers_subnet_id, internal=True
            ),
            public_network_access="Disabled",
        )

        # Define the container app with HedgeDoc
        self.dns_record_name = "hedgedoc"
        self.container_app_name = (
            f"{stack_name}-container-group-{self.dns_record_name}",
        )
        self.container_app = app.ContainerApp(
            f"{self._name}_container_app",
            container_app_name=self.container_app_name,
            resource_group_name=props.resource_group_name,
            managed_environment_id=self.managed_env.id,
            configuration=app.ConfigurationArgs(
                ingress=app.IngressArgs(
                    external=True, target_port=3000, transport="auto"
                ),
                registries=[
                    app.RegistryCredentialsArgs(
                        server=props.dockerhub_credentials.server,
                        username=props.dockerhub_credentials.username,
                        password_secret_ref="registry-token",
                    )
                ],
                secrets=[
                    app.SecretArgs(
                        name="registry-token",
                        value=Output.secret(props.dockerhub_credentials.access_token),
                    ),
                    app.SecretArgs(
                        name="db-admin-password",
                        value=props.db_server_shared_password,
                    ),
                    app.SecretArgs(
                        name="config-json",
                        value=b64encode(
                            hedgedoc_config_json_reader.file_contents(),
                        ),
                    ),
                ],
            ),
            template=app.TemplateArgs(
                containers=[
                    app.ContainerArgs(
                        image="quay.io/hedgedoc/hedgedoc:1.12.0",
                        name="hedgedoc"[:63],
                        env=[
                            app.EnvironmentVarArgs(
                                name="CMD_ALLOW_ANONYMOUS",
                                value="false",
                            ),
                            app.EnvironmentVarArgs(
                                name="CMD_DB_DATABASE",
                                value=db_hedgedoc_documents_name,
                            ),
                            app.EnvironmentVarArgs(
                                name="CMD_DB_DIALECT",
                                value="postgres",
                            ),
                            app.EnvironmentVarArgs(
                                name="CMD_DB_HOST",
                                value=props.db_server_shared.private_ip_address,
                            ),
                            app.EnvironmentVarArgs(
                                name="CMD_DB_PASSWORD",
                                secret_ref="db-admin-password",
                            ),
                            app.EnvironmentVarArgs(
                                name="CMD_DB_PORT",
                                value=Ports.POSTGRESQL,
                            ),
                            app.EnvironmentVarArgs(
                                name="CMD_DB_USERNAME",
                                value=props.db_server_shared.db_server.administrator_login,
                            ),
                            app.EnvironmentVarArgs(
                                name="CMD_DOMAIN",
                                value=Output.concat("hedgedoc.", props.sre_fqdn),
                            ),
                            app.EnvironmentVarArgs(
                                name="CMD_EMAIL",
                                value="false",
                            ),
                            app.EnvironmentVarArgs(
                                name="CMD_LDAP_PROVIDERNAME",
                                value="Data Safe Haven",
                            ),
                            app.EnvironmentVarArgs(
                                name="CMD_LDAP_SEARCHBASE",
                                value=props.ldap_user_search_base,
                            ),
                            app.EnvironmentVarArgs(
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
                            app.EnvironmentVarArgs(
                                name="CMD_LDAP_URL",
                                value=Output.concat(
                                    "ldap://",
                                    props.ldap_server_hostname,
                                    ":",
                                    props.ldap_server_port,
                                ),
                            ),
                            app.EnvironmentVarArgs(
                                name="CMD_LDAP_USERIDFIELD",
                                value=props.ldap_username_attribute,
                            ),
                            app.EnvironmentVarArgs(
                                name="CMD_LOGLEVEL",
                                value=LogLevelParser.service_logging_level(
                                    props.log_level,
                                    "hedgedoc",
                                    SREHedgeDocServerProps.log_level_convert,
                                ),
                            ),
                        ],
                        resources=app.ContainerResourcesArgs(
                            cpu=2,
                            memory="4Gi",
                        ),
                        volume_mounts=[
                            app.VolumeMountArgs(
                                mount_path="/files",
                                volume_name="hedgedoc-files-config-json",
                            ),
                        ],
                    ),
                ],
                volumes=[
                    app.VolumeArgs(
                        name="hedgedoc-files-config-json",
                        secrets=[
                            app.SecretVolumeItemArgs(
                                path="config.json",
                                secret_ref="config-json",
                            ),
                        ],
                    ),
                ],
                scale=app.ScaleArgs(
                    min_replicas=1,
                    max_replicas=2,
                    cooldown_period=300,
                    polling_interval=30,
                    rules=[
                        app.ScaleRuleArgs(
                            name="http-scalar",
                            http=app.HttpScaleRuleArgs(
                                metadata={
                                    "concurrentRequests": "10",
                                }
                            ),
                        ),
                    ],
                ),
            ),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    delete_before_replace=True,
                    depends_on=[
                        db_hedgedoc_documents,
                        props.log_analytics_workspace.workspace,
                    ],
                    replace_on_changes=["containers"],
                ),
            ),
            tags=child_tags,
        )

        # Register the container group in the SRE DNS zone
        self.local_dns = LocalDnsRecordComponent(
            f"{self._name}_hedgedoc_dns_record_set",
            LocalDnsRecordProps(
                base_fqdn=props.sre_fqdn,
                private_ip_address=self.managed_env.static_ip,
                record_name=self.dns_record_name,
                resource_group_name=props.resource_group_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=self.container_app)
            ),
        )

        # Register outputs
        self.hostname = self.local_dns.hostname
