from typing import Protocol

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import (
    authorization,
    containerinstance,
    storage,
)
from pulumi_azure_native.app import (
    AccessMode,
    AppLogsConfigurationArgs,
    AzureFilePropertiesArgs,
    ContainerArgs,
    ContainerResourcesArgs,
    EnvironmentVarArgs,
    Job,
    JobConfigurationArgs,
    JobConfigurationScheduleTriggerConfigArgs,
    JobTemplateArgs,
    LogAnalyticsConfigurationArgs,
    ManagedEnvironment,
    ManagedEnvironmentsStorage,
    ManagedEnvironmentStoragePropertiesArgs,
    ManagedServiceIdentityArgs,
    ManagedServiceIdentityType,
    StorageType,
    TriggerType,
    VnetConfigurationArgs,
    VolumeArgs,
    VolumeMountArgs,
    WorkloadProfileArgs,
)
from pulumi_azure_native.managedidentity import UserAssignedIdentity

from data_safe_haven.functions import seeded_uuid
from data_safe_haven.infrastructure.components import (
    FileShareFile,
    FileShareFileProps,
    LocalDnsRecordComponent,
    OperationalInsightsWorkspace,
)
from data_safe_haven.resources import resources_path
from data_safe_haven.utility import FileReader


class SupportsDnsSidecar(Protocol):
    dns_record_name: str
    container_group_name: str
    local_dns: LocalDnsRecordComponent
    container_group: containerinstance.ContainerGroup


class DnsSidecarProps:
    """Properties of the DnsSidecarComponent"""

    def __init__(
        self,
        container_instances: list[SupportsDnsSidecar],
        cron_expression: str,
        subnet_id: Input[str],
        location: Input[str],
        log_analytics_workspace: Input[OperationalInsightsWorkspace],
        resource_group_name: Input[str],
        replica_timeout: int,
        retry_limit: int,
        sre_fqdn: Input[str],
        subscription_id: Input[str],
        storage_account_name: Input[str],
        storage_account_key: Input[str],
        workload_maximum_count: int,
        workload_minimum_count: int,
    ):
        self.container_instances = container_instances
        self.cron_expression = cron_expression
        self.subnet_id = subnet_id
        self.location = location
        self.log_analytics_workspace = log_analytics_workspace
        self.resource_group_name = resource_group_name
        self.replica_timeout = replica_timeout
        self.retry_limit = retry_limit
        self.sre_fqdn = sre_fqdn
        self.subscription_id = subscription_id
        self.storage_account_name = storage_account_name
        self.storage_account_key = storage_account_key
        self.workload_maximum_count = workload_maximum_count
        self.workload_minimum_count = workload_minimum_count


class DnsSidecarComponent(ComponentResource):

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: DnsSidecarProps,
        opts: ResourceOptions | None = None,
    ):
        super().__init__("dsh:sre:DnsSidecarComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        file_share = storage.FileShare(
            f"{self._name}_file_share",
            access_tier=storage.ShareAccessTier.TRANSACTION_OPTIMIZED,
            account_name=props.storage_account_name,
            resource_group_name=props.resource_group_name,
            share_name="dnssidecar-share",
            share_quota=1,
            signed_identifiers=[],
            opts=child_opts,
        )

        # Upload DNS Monitor Script
        dns_sidecar_script_reader = FileReader(
            resources_path / "dns_sidecar" / "init.sh"
        )

        self.file_share_dns_sidecar_script = FileShareFile(
            f"{self._name}_file_share_dnssidecar_init",
            FileShareFileProps(
                destination_path=dns_sidecar_script_reader.name,
                share_name=file_share.name,
                file_contents=Output.secret(dns_sidecar_script_reader.file_contents()),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=file_share)),
        )

        user_assigned_identity = UserAssignedIdentity(
            f"{self._name}_sidecar",
            location=props.location,
            resource_group_name=props.resource_group_name,
            resource_name_=f"{stack_name}-id-dns-sidecar",
            opts=child_opts,
        )

        for container_instance in props.container_instances:

            # Allowing the managed identity to update DNS Records
            dns_zone_role_definition = authorization.RoleDefinition(
                f"{stack_name}_{container_instance.dns_record_name}_dns_updater_role",
                role_name=f"DNS Zone updater: {container_instance.dns_record_name} ({stack_name})",
                scope=container_instance.local_dns.private_record_set_id,
                description=f"Role for updating {container_instance.dns_record_name}'s DNS records",
                permissions=[
                    authorization.PermissionArgs(
                        actions=[
                            "Microsoft.Network/privateDnsZones/A/read",
                            "Microsoft.Network/privateDnsZones/A/write",
                        ],
                        not_actions=[],
                    )
                ],
                assignable_scopes=[container_instance.local_dns.private_record_set_id],
                opts=ResourceOptions.merge(
                    child_opts,
                    ResourceOptions(
                        depends_on=[container_instance.local_dns.public_dns_record_set],
                        delete_before_replace=True,
                        aliases=[
                            f"urn:pulumi:{stack_name}::data-safe-haven::azure-native:authorization:RoleDefinition::{self._name}_{container_instance.dns_record_name}_dns_updater_role"
                        ],
                    ),
                ),
            )

            self.dns_zone_role_assignment = authorization.RoleAssignment(
                f"{stack_name}_{container_instance.dns_record_name}_dnssidecar_dns_updater_job_role_assignment",
                principal_id=user_assigned_identity.principal_id,
                principal_type=authorization.PrincipalType.SERVICE_PRINCIPAL,
                role_assignment_name=str(
                    seeded_uuid(
                        f"{stack_name} DNS updater for {container_instance.dns_record_name}"
                    )
                ),
                role_definition_id=dns_zone_role_definition.id,
                scope=container_instance.local_dns.private_record_set_id,
                opts=ResourceOptions.merge(
                    child_opts,
                    ResourceOptions(
                        depends_on=[dns_zone_role_definition],
                        delete_before_replace=True,
                        aliases=[
                            f"urn:pulumi:{stack_name}::data-safe-haven::dsh:sre:DnsSidecarComponent$azure-native:authorization:RoleAssignment::{self._name}_{container_instance.dns_record_name}_dnssidecar_dns_updater_job_role_assignment"
                        ],
                    ),
                ),
            )

            # Allow the managed identity to retrieve the container group IP
            container_group_role_definition = authorization.RoleDefinition(
                f"{stack_name}_{container_instance.dns_record_name}_dnssidecar_ip_reader_role",
                role_name=f"Container group reader: {container_instance.dns_record_name} ({stack_name})",
                scope=container_instance.container_group.id,
                description=f"Role for reading {container_instance.dns_record_name}'s container group",
                permissions=[
                    authorization.PermissionArgs(
                        actions=[
                            "Microsoft.ContainerInstance/containerGroups/read",
                        ],
                        not_actions=[],
                    )
                ],
                assignable_scopes=[container_instance.container_group.id],
                opts=ResourceOptions.merge(
                    child_opts,
                    ResourceOptions(
                        depends_on=[container_instance.container_group],
                        delete_before_replace=True,
                        aliases=[
                            f"urn:pulumi:{stack_name}::data-safe-haven::azure-native:authorization:RoleDefinition::{self._name}_{container_instance.dns_record_name}_dnssidecar_ip_reader_role"
                        ],
                    ),
                ),
            )

            self.container_group_role_assignment = authorization.RoleAssignment(
                f"{stack_name}_{container_instance.dns_record_name}_dnssidecar_ip_reader_job_role_assignment",
                principal_id=user_assigned_identity.principal_id,
                principal_type=authorization.PrincipalType.SERVICE_PRINCIPAL,
                role_assignment_name=str(
                    seeded_uuid(
                        f"{stack_name} IP Reader for Job {container_instance.dns_record_name}"
                    )
                ),
                role_definition_id=container_group_role_definition.id,
                scope=container_instance.container_group.id,
                opts=ResourceOptions.merge(
                    child_opts,
                    ResourceOptions(
                        depends_on=[container_group_role_definition],
                        delete_before_replace=True,
                        aliases=[
                            f"urn:pulumi:{stack_name}::data-safe-haven::dsh:sre:DnsSidecarComponent$azure-native:authorization:RoleAssignment::{self._name}_{container_instance.dns_record_name}_dnssidecar_ip_reader_job_role_assignment"
                        ],
                    ),
                ),
            )

        workload_profile_name: str = "dnssidecarprof"
        managed_environment = ManagedEnvironment(
            f"{self._name}_managed-environment".replace("_", "-"),
            app_logs_configuration=AppLogsConfigurationArgs(
                destination="log-analytics",
                log_analytics_configuration=LogAnalyticsConfigurationArgs(
                    customer_id=props.log_analytics_workspace.workspace_id,
                    shared_key=props.log_analytics_workspace.workspace_key,
                ),
            ),
            resource_group_name=props.resource_group_name,
            location=props.location,
            vnet_configuration=VnetConfigurationArgs(
                infrastructure_subnet_id=props.subnet_id,
                internal=True,
            ),
            workload_profiles=[
                WorkloadProfileArgs(
                    name=workload_profile_name,
                    maximum_count=props.workload_maximum_count,
                    minimum_count=props.workload_minimum_count,
                    workload_profile_type="D4",
                )
            ],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    depends_on=[props.log_analytics_workspace.workspace],
                ),
            ),
        )

        managed_environment_storage = ManagedEnvironmentsStorage(
            f"{self._name}_managed_environment_storage".replace("_", "-")[:24],
            environment_name=managed_environment.name,
            resource_group_name=props.resource_group_name,
            properties=ManagedEnvironmentStoragePropertiesArgs(
                azure_file=AzureFilePropertiesArgs(
                    access_mode=AccessMode.READ_ONLY,
                    account_key=props.storage_account_key,
                    account_name=props.storage_account_name,
                    share_name=file_share.name,
                )
            ),
        )

        volume_name: str = "dns-sidecar-volume"
        self.job = Job(
            f"{self._name}-job-dns-sidecar".replace("_", "-")[:24],
            resource_group_name=props.resource_group_name,
            environment_id=managed_environment.id,
            identity=ManagedServiceIdentityArgs(
                type=ManagedServiceIdentityType.USER_ASSIGNED,
                user_assigned_identities=[user_assigned_identity.id],
            ),
            configuration=JobConfigurationArgs(
                trigger_type=TriggerType.SCHEDULE,
                replica_timeout=props.replica_timeout,
                replica_retry_limit=props.retry_limit,
                schedule_trigger_config=JobConfigurationScheduleTriggerConfigArgs(
                    cron_expression=props.cron_expression
                ),
            ),
            template=JobTemplateArgs(
                containers=[
                    ContainerArgs(
                        image="mcr.microsoft.com/azure-cli:2.90.0",
                        name="dnssidecar",
                        command=("/bin/sh", "/mnt/init/init.sh"),
                        resources=ContainerResourcesArgs(
                            cpu=0.5,
                            memory="1.0Gi",
                        ),
                        env=[
                            EnvironmentVarArgs(
                                name="CLIENT_ID",
                                value=user_assigned_identity.client_id,
                            ),
                            EnvironmentVarArgs(
                                name="STACK_NAME",
                                value=stack_name,
                            ),
                            EnvironmentVarArgs(
                                name="RESOURCE_GROUP",
                                value=props.resource_group_name,
                            ),
                            EnvironmentVarArgs(
                                name="SUBSCRIPTION_ID",
                                value=props.subscription_id,
                            ),
                            EnvironmentVarArgs(
                                name="RECORD_NAMES_CONTAINER_GROUPS",
                                value=",".join(
                                    [
                                        f"{container_instance.dns_record_name} {container_instance.container_group_name}"
                                        for container_instance in props.container_instances
                                    ]
                                ),
                            ),
                            EnvironmentVarArgs(
                                name="PRIVATE_ZONE_NAME",
                                value=Output.concat("privatelink.", props.sre_fqdn),
                            ),
                        ],
                        volume_mounts=[
                            VolumeMountArgs(
                                mount_path="/mnt/init",
                                volume_name=volume_name,
                            )
                        ],
                    )
                ],
                volumes=[
                    VolumeArgs(
                        name=volume_name,
                        storage_type=StorageType.AZURE_FILE,
                        storage_name=managed_environment_storage.name,
                    )
                ],
            ),
            workload_profile_name=workload_profile_name,
        )
