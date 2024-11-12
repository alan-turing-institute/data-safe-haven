"""Pulumi component for SRE backup"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, ResourceOptions


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
