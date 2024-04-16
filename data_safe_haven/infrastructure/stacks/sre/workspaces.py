import pathlib
from collections.abc import Mapping
from typing import Any

import chevron
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

from data_safe_haven.exceptions import DataSafeHavenPulumiError
from data_safe_haven.functions import b64encode, replace_separators
from data_safe_haven.infrastructure.common import (
    get_available_ips_from_subnet,
    get_name_from_rg,
    get_name_from_subnet,
    get_name_from_vnet,
)
from data_safe_haven.infrastructure.components import (
    FileUpload,
    FileUploadProps,
    LinuxVMComponentProps,
    VMComponent,
)
from data_safe_haven.resources import resources_path
from data_safe_haven.utility import FileReader


class SREWorkspacesProps:
    """Properties for SREWorkspacesComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        ldap_group_filter: Input[str],
        ldap_group_search_base: Input[str],
        ldap_server_hostname: Input[str],
        ldap_server_port: Input[int],
        ldap_user_filter: Input[str],
        ldap_user_search_base: Input[str],
        linux_update_server_ip: Input[str],
        location: Input[str],
        log_analytics_workspace_id: Input[str],
        log_analytics_workspace_key: Input[str],
        sre_fqdn: Input[str],
        sre_name: Input[str],
        storage_account_data_private_user_name: Input[str],
        storage_account_data_private_sensitive_name: Input[str],
        subnet_workspaces: Input[network.GetSubnetResult],
        subscription_name: Input[str],
        virtual_network_resource_group: Input[resources.ResourceGroup],
        virtual_network: Input[network.VirtualNetwork],
        vm_details: list[tuple[int, str]],  # this must *not* be passed as an Input[T]
    ) -> None:
        self.admin_password = Output.secret(admin_password)
        self.admin_username = "dshadmin"
        self.ldap_group_filter = ldap_group_filter
        self.ldap_group_search_base = ldap_group_search_base
        self.ldap_server_hostname = ldap_server_hostname
        self.ldap_server_port = Output.from_input(ldap_server_port).apply(str)
        self.ldap_user_filter = ldap_user_filter
        self.ldap_user_search_base = ldap_user_search_base
        self.linux_update_server_ip = linux_update_server_ip
        self.location = location
        self.log_analytics_workspace_id = log_analytics_workspace_id
        self.log_analytics_workspace_key = log_analytics_workspace_key
        self.sre_fqdn = sre_fqdn
        self.sre_name = sre_name
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
        self.virtual_network_resource_group_name = Output.from_input(
            virtual_network_resource_group
        ).apply(get_name_from_rg)
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
        child_tags = tags if tags else {}

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-workspaces",
            opts=child_opts,
            tags=child_tags,
        )

        # Load cloud-init file
        b64cloudinit = Output.all(
            ldap_group_filter=props.ldap_group_filter,
            ldap_group_search_base=props.ldap_group_search_base,
            ldap_server_hostname=props.ldap_server_hostname,
            ldap_server_port=props.ldap_server_port,
            ldap_user_filter=props.ldap_user_filter,
            ldap_user_search_base=props.ldap_user_search_base,
            linux_update_server_ip=props.linux_update_server_ip,
            sre_fqdn=props.sre_fqdn,
            storage_account_data_private_user_name=props.storage_account_data_private_user_name,
            storage_account_data_private_sensitive_name=props.storage_account_data_private_sensitive_name,
        ).apply(lambda kwargs: self.read_cloudinit(**kwargs))

        # Deploy a variable number of VMs depending on the input parameters
        vms = [
            VMComponent(
                replace_separators(f"{self._name}_vm_workspace_{vm_idx+1:02d}", "_"),
                LinuxVMComponentProps(
                    admin_password=props.admin_password,
                    admin_username=props.admin_username,
                    b64cloudinit=b64cloudinit,
                    ip_address_private=props.vm_ip_addresses[vm_idx],
                    location=props.location,
                    log_analytics_workspace_id=props.log_analytics_workspace_id,
                    log_analytics_workspace_key=props.log_analytics_workspace_key,
                    resource_group_name=resource_group.name,
                    subnet_name=props.subnet_workspaces_name,
                    virtual_network_name=props.virtual_network_name,
                    virtual_network_resource_group_name=props.virtual_network_resource_group_name,
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

        # Upload smoke tests
        mustache_values = {
            "check_uninstallable_packages": "0",
        }
        file_uploads = [
            (FileReader(resources_path / "workspace" / "run_all_tests.bats"), "0444")
        ]
        for test_file in pathlib.Path(resources_path / "workspace").glob("test*"):
            file_uploads.append((FileReader(test_file), "0444"))
        for vm, vm_output in zip(vms, vm_outputs, strict=True):
            outputs: dict[str, Output[str]] = {}
            for file_upload, file_permissions in file_uploads:
                file_smoke_test = FileUpload(
                    replace_separators(f"{self._name}_file_{file_upload.name}", "_"),
                    FileUploadProps(
                        file_contents=file_upload.file_contents(
                            mustache_values=mustache_values
                        ),
                        file_hash=file_upload.sha256(),
                        file_permissions=file_permissions,
                        file_target=f"/opt/tests/{file_upload.name}",
                        subscription_name=props.subscription_name,
                        vm_name=vm.vm_name,
                        vm_resource_group_name=resource_group.name,
                    ),
                    opts=child_opts,
                )
                outputs[file_upload.name] = file_smoke_test.script_output
            vm_output["file_uploads"] = outputs

        # Register outputs
        self.resource_group = resource_group

        # Register exports
        self.exports = {
            "vm_outputs": vm_outputs,
        }

    def read_cloudinit(
        self,
        ldap_group_filter: str,
        ldap_group_search_base: str,
        ldap_server_hostname: str,
        ldap_server_port: str,
        ldap_user_filter: str,
        ldap_user_search_base: str,
        linux_update_server_ip: str,
        sre_fqdn: str,
        storage_account_data_private_sensitive_name: str,
        storage_account_data_private_user_name: str,
    ) -> str:
        with open(
            resources_path / "workspace" / "workspace.cloud_init.mustache.yaml",
            encoding="utf-8",
        ) as f_cloudinit:
            mustache_values = {
                "ldap_group_filter": ldap_group_filter,
                "ldap_group_search_base": ldap_group_search_base,
                "ldap_server_hostname": ldap_server_hostname,
                "ldap_server_port": ldap_server_port,
                "ldap_user_filter": ldap_user_filter,
                "ldap_user_search_base": ldap_user_search_base,
                "linux_update_server_ip": linux_update_server_ip,
                "sre_fqdn": sre_fqdn,
                "storage_account_data_private_user_name": storage_account_data_private_user_name,
                "storage_account_data_private_sensitive_name": storage_account_data_private_sensitive_name,
            }
            cloudinit = chevron.render(f_cloudinit, mustache_values)
            return b64encode(cloudinit)
