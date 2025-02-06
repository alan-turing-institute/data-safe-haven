"""Pulumi component for SRE backup"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network

from data_safe_haven.functions import b64encode, replace_separators
from data_safe_haven.infrastructure.common import (
    get_name_from_subnet,
    get_name_from_vnet,
)
from data_safe_haven.infrastructure.components import LinuxVMComponentProps, VMComponent


class SREBackupProps:
    """Properties for SREBackupComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        admin_username: Input[str],
        apt_proxy_server_hostname: Input[str],
        data_collection_rule_id: Input[str],
        data_collection_endpoint_id: Input[str],
        location: Input[str],
        maintenance_configuration_id: Input[str],
        resource_group_name: Input[str],
        storage_account_data_private_sensitive_name: Input[str],
        storage_account_data_private_user_name: Input[str],
        storage_account_desired_state_name: Input[str],
        subnet_backup: Input[network.GetSubnetResult],
        virtual_network: Input[network.VirtualNetwork],
    ) -> None:
        self.admin_password = admin_password
        self.admin_username = admin_username
        self.apt_proxy_server_hostname = apt_proxy_server_hostname
        self.data_collection_rule_id = data_collection_rule_id
        self.data_collection_endpoint_id = data_collection_endpoint_id
        self.location = location
        self.maintenance_configuration_id = maintenance_configuration_id
        self.resource_group_name = resource_group_name
        self.storage_account_data_private_sensitive_name = (
            storage_account_data_private_sensitive_name
        )
        self.storage_account_data_private_user_name = (
            storage_account_data_private_user_name
        )
        self.storage_account_desired_state_name = storage_account_desired_state_name
        self.subnet_backup_name = Output.from_input(subnet_backup).apply(
            get_name_from_subnet
        )
        self.virtual_network_name = Output.from_input(virtual_network).apply(
            get_name_from_vnet
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

        # Template cloud init
        cloudinit = Output.all(
            apt_proxy_server_hostname=props.apt_proxy_server_hostname,
            storage_account_desired_state_name=props.storage_account_desired_state_name,
            storage_account_data_private_user_name=props.storage_account_data_private_user_name,
            storage_account_data_private_sensitive_name=props.storage_account_data_private_sensitive_name,
        ).apply(lambda kwargs: self.template_cloudinit(**kwargs))

        # Backup virtual machine
        VMComponent(
            replace_separators(f"{self._name}_vm_backup", "_"),
            LinuxVMComponentProps(
                admin_password=props.admin_password,
                admin_username=props.admin_username,
                b64cloudinit=cloudinit.apply(b64encode),
                data_collection_rule_id=props.data_collection_rule_id,
                data_collection_endpoint_id=props.data_collection_endpoint_id,
                ip_address_private=...,
                location=props.location,
                maintenance_configuration_id=props.maintenance_configuration_id,
                resource_group_name=props.resource_group_name,
                subnet_name=props.subnet_backup_name,
                virtual_network_name=props.virtual_network_name,
                virtual_network_resource_group_name=props.resource_group_name,
                vm_name=Output.concat(stack_name, "-vm-backup").apply(
                    lambda s: replace_separators(s, "-")
                ),
                vm_size="Standard_B2s_v2",
            ),
            opts=child_opts,
            tags=child_tags,
        )
