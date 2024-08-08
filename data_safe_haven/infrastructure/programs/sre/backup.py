"""Pulumi component for SRE backup"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, ResourceOptions
from pulumi_azure_native import dataprotection


class SREBackupProps:
    """Properties for SREBackupComponent"""

    def __init__(
        self,
        location: Input[str],
        resource_group_name: Input[str],
        storage_account_data_private_sensitive_id: Input[str],
        storage_account_data_private_sensitive_name: Input[str],
    ) -> None:
        self.location = location
        self.resource_group_name = resource_group_name
        self.storage_account_data_private_sensitive_id = (
            storage_account_data_private_sensitive_id
        )
        self.storage_account_data_private_sensitive_name = (
            storage_account_data_private_sensitive_name
        )


class SREBackupComponent(ComponentResource):
    """Deploy SRE backup with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREBackupProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:BackupComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "backup"} | (tags if tags else {})

        # Deploy backup vault
        backup_vault = dataprotection.BackupVault(
            f"{self._name}_backup_vault",
            identity=dataprotection.DppIdentityDetailsArgs(
                type="SystemAssigned",
            ),
            location=props.location,
            properties=dataprotection.BackupVaultArgs(
                storage_settings=[
                    dataprotection.StorageSettingArgs(
                        datastore_type=dataprotection.StorageSettingStoreTypes.VAULT_STORE,
                        type=dataprotection.StorageSettingTypes.LOCALLY_REDUNDANT,
                    )
                ],
            ),
            resource_group_name=props.resource_group_name,
            vault_name=f"{stack_name}-bv-backup",
            opts=child_opts,
            tags=child_tags,
        )

        # Backup policy for blobs
        backup_policy_blobs = dataprotection.BackupPolicy(
            f"{self._name}_backup_policy_blobs",
            backup_policy_name="backup-policy-blobs",
            properties=dataprotection.BackupPolicyArgs(
                datasource_types=["Microsoft.Storage/storageAccounts/blobServices"],
                object_type="BackupPolicy",
                policy_rules=[
                    # Retain for 30 days
                    dataprotection.AzureRetentionRuleArgs(
                        is_default=True,
                        lifecycles=[
                            dataprotection.SourceLifeCycleArgs(
                                delete_after=dataprotection.AbsoluteDeleteOptionArgs(
                                    duration="P30D",
                                    object_type="AbsoluteDeleteOption",
                                ),
                                source_data_store=dataprotection.DataStoreInfoBaseArgs(
                                    data_store_type=dataprotection.DataStoreTypes.OPERATIONAL_STORE,
                                    object_type="DataStoreInfoBase",
                                ),
                            ),
                        ],
                        name="Default",
                        object_type="AzureRetentionRule",
                    ),
                ],
            ),
            resource_group_name=props.resource_group_name,
            vault_name=backup_vault.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=backup_vault)
            ),
        )

        # Backup policy for disks
        dataprotection.BackupPolicy(
            f"{self._name}_backup_policy_disks",
            backup_policy_name="backup-policy-disks",
            properties=dataprotection.BackupPolicyArgs(
                datasource_types=["Microsoft.Compute/disks"],
                object_type="BackupPolicy",
                policy_rules=[
                    # Backup at 02:00 every day
                    dataprotection.AzureBackupRuleArgs(
                        backup_parameters=dataprotection.AzureBackupParamsArgs(
                            backup_type="Incremental",
                            object_type="AzureBackupParams",
                        ),
                        data_store=dataprotection.DataStoreInfoBaseArgs(
                            data_store_type=dataprotection.DataStoreTypes.OPERATIONAL_STORE,
                            object_type="DataStoreInfoBase",
                        ),
                        name="BackupDaily",
                        object_type="AzureBackupRule",
                        trigger=dataprotection.ScheduleBasedTriggerContextArgs(
                            object_type="ScheduleBasedTriggerContext",
                            schedule=dataprotection.BackupScheduleArgs(
                                repeating_time_intervals=[
                                    "R/2023-01-01T02:00:00+00:00/P1D"
                                ],
                            ),
                            tagging_criteria=[
                                dataprotection.TaggingCriteriaArgs(
                                    is_default=True,
                                    tag_info=dataprotection.RetentionTagArgs(
                                        tag_name="Default",
                                    ),
                                    tagging_priority=99,
                                )
                            ],
                        ),
                    ),
                    # Retain for 30 days
                    dataprotection.AzureRetentionRuleArgs(
                        is_default=True,
                        lifecycles=[
                            dataprotection.SourceLifeCycleArgs(
                                delete_after=dataprotection.AbsoluteDeleteOptionArgs(
                                    duration="P30D",
                                    object_type="AbsoluteDeleteOption",
                                ),
                                source_data_store=dataprotection.DataStoreInfoBaseArgs(
                                    data_store_type=dataprotection.DataStoreTypes.OPERATIONAL_STORE,
                                    object_type="DataStoreInfoBase",
                                ),
                            ),
                        ],
                        name="Default",
                        object_type="AzureRetentionRule",
                    ),
                ],
            ),
            resource_group_name=props.resource_group_name,
            vault_name=backup_vault.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=backup_vault)
            ),
        )

        # Backup instance for blobs
        dataprotection.BackupInstance(
            f"{self._name}_backup_instance_blobs",
            backup_instance_name="backup-instance-blobs",
            properties=dataprotection.BackupInstanceArgs(
                data_source_info=dataprotection.DatasourceArgs(
                    resource_id=props.storage_account_data_private_sensitive_id,
                    datasource_type="Microsoft.Storage/storageAccounts/blobServices",
                    object_type="Datasource",
                    resource_location=props.location,
                    resource_name=props.storage_account_data_private_sensitive_name,
                    resource_type="Microsoft.Storage/storageAccounts",
                    resource_uri=props.storage_account_data_private_sensitive_id,
                ),
                object_type="BackupInstance",
                policy_info=dataprotection.PolicyInfoArgs(
                    policy_id=backup_policy_blobs.id,
                ),
                friendly_name="BlobBackupSensitiveData",
            ),
            resource_group_name=props.resource_group_name,
            vault_name=backup_vault.name,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=backup_policy_blobs)
            ),
        )

        # Backup instance for disks
        # We currently have no disks except OS disks so no backup is needed
        # This may change in future, so we leave the policy above
