import pathlib
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
from data_safe_haven.infrastructure.components.composite.virtual_machine import (
    LinuxVMProps,
    VMComponent,
)


class SREWorkspacesProps:
    """Properties for SREWorkspacesComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        domain_sid: Input[str],
        ldap_bind_dn: Input[str],
        ldap_group_search_base: Input[str],
        ldap_root_dn: Input[str],
        ldap_search_password: Input[str],
        ldap_server_ip: Input[str],
        ldap_user_search_base: Input[str],
        ldap_user_security_group_name: Input[str],
        linux_update_server_ip: Input[str],
        location: Input[str],
        log_analytics_workspace_id: Input[str],
        log_analytics_workspace_key: Input[str],
        sre_fqdn: Input[str],
        sre_name: Input[str],
        storage_account_data_private_user_name: Input[str],
        storage_account_data_private_sensitive_name: Input[str],
        subnet_workspaces: Input[network.GetSubnetResult],
        virtual_network_resource_group: Input[resources.ResourceGroup],
        virtual_network: Input[network.VirtualNetwork],
        vm_details: list[tuple[int, str]],  # this must *not* be passed as an Input[T]
    ) -> None:
        self.admin_password = Output.secret(admin_password)
        self.admin_username = "dshadmin"
        self.domain_sid = domain_sid
        self.ldap_bind_dn = ldap_bind_dn
        self.ldap_group_search_base = ldap_group_search_base
        self.ldap_root_dn = ldap_root_dn
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.ldap_user_search_base = ldap_user_search_base
        self.ldap_user_security_group_name = ldap_user_security_group_name
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
    ) -> None:
        super().__init__("dsh:sre:WorkspacesComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-workspaces",
            opts=child_opts,
        )

        # Load cloud-init file
        b64cloudinit = Output.all(
            domain_sid=props.domain_sid,
            ldap_bind_dn=props.ldap_bind_dn,
            ldap_group_search_base=props.ldap_group_search_base,
            ldap_root_dn=props.ldap_root_dn,
            ldap_search_password=props.ldap_search_password,
            ldap_user_security_group_name=props.ldap_user_security_group_name,
            ldap_server_ip=props.ldap_server_ip,
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
                LinuxVMProps(
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
            )
            for vm_idx, vm_size in props.vm_details
        ]

        # Get details for each deployed VM
        vm_outputs = [
            {
                "ip_address": vm.ip_address_private,
                "name": vm.vm_name,
                "sku": vm.vm_size,
            }
            for vm in vms
        ]

        # Register outputs
        self.resource_group = resource_group

        # Register exports
        self.exports = {
            "vm_outputs": vm_outputs,
        }

    def read_cloudinit(
        self,
        domain_sid: str,
        ldap_bind_dn: str,
        ldap_group_search_base: str,
        ldap_root_dn: str,
        ldap_search_password: str,
        ldap_user_security_group_name: str,
        ldap_server_ip: str,
        ldap_user_search_base: str,
        linux_update_server_ip: str,
        sre_fqdn: str,
        storage_account_data_private_user_name: str,
        storage_account_data_private_sensitive_name: str,
    ) -> str:
        resources_path = (
            pathlib.Path(__file__).parent.parent.parent / "resources" / "workspace"
        )
        with open(
            resources_path / "workspace.cloud_init.mustache.yaml", encoding="utf-8"
        ) as f_cloudinit:
            mustache_values = {
                "domain_sid": domain_sid,
                "ldap_bind_dn": ldap_bind_dn,
                "ldap_group_search_base": ldap_group_search_base,
                "ldap_root_dn": ldap_root_dn,
                "ldap_search_password": ldap_search_password,
                "ldap_user_security_group_name": ldap_user_security_group_name,
                "ldap_server_ip": ldap_server_ip,
                "ldap_user_search_base": ldap_user_search_base,
                "linux_update_server_ip": linux_update_server_ip,
                "sre_fqdn": sre_fqdn,
                "storage_account_data_private_user_name": storage_account_data_private_user_name,
                "storage_account_data_private_sensitive_name": storage_account_data_private_sensitive_name,
            }
            cloudinit = chevron.render(f_cloudinit, mustache_values)
            return b64encode(cloudinit)
