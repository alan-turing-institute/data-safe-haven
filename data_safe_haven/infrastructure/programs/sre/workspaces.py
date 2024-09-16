from collections.abc import Mapping
from typing import Any

import chevron
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network

from data_safe_haven.exceptions import DataSafeHavenPulumiError
from data_safe_haven.functions import b64encode, replace_separators
from data_safe_haven.infrastructure.common import (
    get_available_ips_from_subnet,
    get_name_from_subnet,
    get_name_from_vnet,
)
from data_safe_haven.infrastructure.components import LinuxVMComponentProps, VMComponent
from data_safe_haven.logging import get_logger
from data_safe_haven.resources import resources_path


class SREWorkspacesProps:
    """Properties for SREWorkspacesComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        apt_proxy_server_hostname: Input[str],
        clamav_mirror_hostname: Input[str],
        data_collection_endpoint_id: Input[str],
        data_collection_rule_id: Input[str],
        database_service_admin_password: Input[str],
        internal_gitea_hostname: Input[str],
        hedgedoc_hostname: Input[str],
        ldap_group_filter: Input[str],
        ldap_group_search_base: Input[str],
        ldap_server_hostname: Input[str],
        ldap_server_port: Input[int],
        ldap_user_filter: Input[str],
        ldap_user_search_base: Input[str],
        location: Input[str],
        maintenance_configuration_id: Input[str],
        resource_group_name: Input[str],
        software_repository_hostname: Input[str],
        sre_name: Input[str],
        storage_account_data_desired_state_name: Input[str],
        storage_account_data_private_sensitive_name: Input[str],
        storage_account_data_private_user_name: Input[str],
        subnet_workspaces: Input[network.GetSubnetResult],
        subscription_name: Input[str],
        virtual_network: Input[network.VirtualNetwork],
        vm_details: list[tuple[int, str]],  # this must *not* be passed as an Input[T]
        external_gitea_hostname: Input[str] | None = None,
    ) -> None:
        self.admin_password = Output.secret(admin_password)
        self.admin_username = "dshadmin"
        self.apt_proxy_server_hostname = apt_proxy_server_hostname
        self.clamav_mirror_hostname = clamav_mirror_hostname
        self.data_collection_rule_id = data_collection_rule_id
        self.data_collection_endpoint_id = data_collection_endpoint_id
        self.database_service_admin_password = database_service_admin_password
        self.internal_gitea_hostname = internal_gitea_hostname
        self.external_gitea_hostname = external_gitea_hostname
        self.hedgedoc_hostname = hedgedoc_hostname
        self.ldap_group_filter = ldap_group_filter
        self.ldap_group_search_base = ldap_group_search_base
        self.ldap_server_hostname = ldap_server_hostname
        self.ldap_server_port = Output.from_input(ldap_server_port).apply(str)
        self.ldap_user_filter = ldap_user_filter
        self.ldap_user_search_base = ldap_user_search_base
        self.location = location
        self.maintenance_configuration_id = maintenance_configuration_id
        self.resource_group_name = resource_group_name
        self.software_repository_hostname = software_repository_hostname
        self.sre_name = sre_name
        self.storage_account_data_desired_state_name = (
            storage_account_data_desired_state_name
        )
        self.storage_account_data_private_user_name = (
            storage_account_data_private_user_name
        )
        self.storage_account_data_private_sensitive_name = (
            storage_account_data_private_sensitive_name
        )
        self.subscription_name = subscription_name
        self.virtual_network_name = Output.from_input(virtual_network).apply(
            get_name_from_vnet
        )
        self.subnet_workspaces_name = Output.from_input(subnet_workspaces).apply(
            get_name_from_subnet
        )
        self.vm_ip_addresses = Output.all(subnet_workspaces, vm_details).apply(
            lambda args: self.get_ip_addresses(subnet=args[0], vm_details=args[1])
        )
        self.vm_details = vm_details

    def get_ip_addresses(self, subnet: Any, vm_details: Any) -> list[str]:
        if not isinstance(subnet, network.GetSubnetResult):
            DataSafeHavenPulumiError(f"'subnet' has invalid type {type(subnet)}")
        if not isinstance(vm_details, list):
            DataSafeHavenPulumiError(
                f"'vm_details' has invalid type {type(vm_details)}"
            )
        return get_available_ips_from_subnet(subnet)[: len(vm_details)]


class SREWorkspacesComponent(ComponentResource):
    """Deploy workspaces with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREWorkspacesProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:WorkspacesComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "workspaces"} | (tags if tags else {})

        # Load cloud-init file
        cloudinit = Output.all(
            apt_proxy_server_hostname=props.apt_proxy_server_hostname,
            clamav_mirror_hostname=props.clamav_mirror_hostname,
            database_service_admin_password=props.database_service_admin_password,
            gitea_hostname=props.internal_gitea_hostname,
            hedgedoc_hostname=props.hedgedoc_hostname,
            ldap_group_filter=props.ldap_group_filter,
            ldap_group_search_base=props.ldap_group_search_base,
            ldap_server_hostname=props.ldap_server_hostname,
            ldap_server_port=props.ldap_server_port,
            ldap_user_filter=props.ldap_user_filter,
            ldap_user_search_base=props.ldap_user_search_base,
            software_repository_hostname=props.software_repository_hostname,
            storage_account_data_desired_state_name=props.storage_account_data_desired_state_name,
            storage_account_data_private_user_name=props.storage_account_data_private_user_name,
            storage_account_data_private_sensitive_name=props.storage_account_data_private_sensitive_name,
        ).apply(lambda kwargs: self.template_cloudinit(**kwargs))

        # Deploy a variable number of VMs depending on the input parameters
        vms = [
            VMComponent(
                replace_separators(f"{self._name}_vm_workspace_{vm_idx+1:02d}", "_"),
                LinuxVMComponentProps(
                    admin_password=props.admin_password,
                    admin_username=props.admin_username,
                    b64cloudinit=cloudinit.apply(b64encode),
                    data_collection_rule_id=props.data_collection_rule_id,
                    data_collection_endpoint_id=props.data_collection_endpoint_id,
                    ip_address_private=props.vm_ip_addresses[vm_idx],
                    location=props.location,
                    maintenance_configuration_id=props.maintenance_configuration_id,
                    resource_group_name=props.resource_group_name,
                    subnet_name=props.subnet_workspaces_name,
                    virtual_network_name=props.virtual_network_name,
                    virtual_network_resource_group_name=props.resource_group_name,
                    vm_name=Output.concat(
                        stack_name, "-vm-workspace-", f"{vm_idx+1:02d}"
                    ).apply(lambda s: replace_separators(s, "-")),
                    vm_size=vm_size,
                ),
                opts=child_opts,
                tags=child_tags,
            )
            for vm_idx, vm_size in props.vm_details
        ]

        # Get details for each deployed VM
        vm_outputs: list[dict[str, Any]] = [
            {
                "ip_address": vm.ip_address_private,
                "name": vm.vm_name,
                "sku": vm.vm_size,
            }
            for vm in vms
        ]

        # Register exports
        self.exports = {
            "vm_outputs": vm_outputs,
        }

    @staticmethod
    def template_cloudinit(**kwargs: str) -> str:
        logger = get_logger()
        with open(
            resources_path / "workspace" / "workspace.cloud_init.mustache.yaml",
            encoding="utf-8",
        ) as f_cloudinit:
            cloudinit = chevron.render(f_cloudinit, kwargs)
            logger.debug(
                f"Generated cloud-init config: {cloudinit.replace('\n', r'\n')}"
            )
            return cloudinit
