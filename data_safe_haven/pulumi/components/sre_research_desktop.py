# Standard library imports
import pathlib
from typing import Any, List, Optional, Tuple

# Third party imports
import chevron
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

# Local imports
from data_safe_haven.exceptions import DataSafeHavenPulumiException
from data_safe_haven.helpers import b64encode, replace_separators
from data_safe_haven.pulumi.common.transformations import (
    get_available_ips_from_subnet,
    get_name_from_rg,
    get_name_from_subnet,
    get_name_from_vnet,
)
from .virtual_machine import LinuxVMProps, VMComponent


class SREResearchDesktopProps:
    """Properties for SREResearchDesktopComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        domain_sid: Input[str],
        ldap_root_dn: Input[str],
        ldap_search_password: Input[str],
        ldap_server_ip: Input[str],
        linux_update_server_ip: Input[str],
        location: Input[str],
        log_analytics_workspace_id: Input[str],
        log_analytics_workspace_key: Input[str],
        storage_account_userdata_name: Input[str],
        storage_account_securedata_name: Input[str],
        security_group_name: Input[str],
        subnet_research_desktops: Input[network.GetSubnetResult],
        virtual_network_resource_group: Input[resources.ResourceGroup],
        virtual_network: Input[network.VirtualNetwork],
        vm_details: List[
            Tuple[int, str, str]
        ],  # this must *not* be passed as an Input[T]
    ):
        self.admin_password = Output.secret(admin_password)
        self.admin_username = "dshadmin"
        self.domain_sid = domain_sid
        self.ldap_root_dn = ldap_root_dn
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.linux_update_server_ip = linux_update_server_ip
        self.location = location
        self.log_analytics_workspace_id = log_analytics_workspace_id
        self.log_analytics_workspace_key = log_analytics_workspace_key
        self.storage_account_userdata_name = storage_account_userdata_name
        self.storage_account_securedata_name = storage_account_securedata_name
        self.security_group_name = security_group_name
        self.virtual_network_name = Output.from_input(virtual_network).apply(
            get_name_from_vnet
        )
        self.subnet_research_desktops_name = Output.from_input(
            subnet_research_desktops
        ).apply(get_name_from_subnet)
        self.virtual_network_resource_group_name = Output.from_input(
            virtual_network_resource_group
        ).apply(get_name_from_rg)
        self.vm_ip_addresses = Output.all(subnet_research_desktops, vm_details).apply(
            lambda args: self.get_ip_addresses(subnet=args[0], vm_details=args[1])
        )
        self.vm_details = vm_details

    def get_ip_addresses(self, subnet: Any, vm_details: Any) -> List[str]:
        if not isinstance(subnet, network.GetSubnetResult):
            DataSafeHavenPulumiException(f"'subnet' has invalid type {type(subnet)}")
        if not isinstance(vm_details, list):
            DataSafeHavenPulumiException(
                f"'vm_details' has invalid type {type(vm_details)}"
            )
        return get_available_ips_from_subnet(subnet)[: len(vm_details)]


class SREResearchDesktopComponent(ComponentResource):
    """Deploy secure research desktops with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SREResearchDesktopProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:sre:SREResearchDesktopComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-research-desktops",
            opts=child_opts,
        )

        # Load cloud-init file
        b64cloudinit = Output.all(
            domain_sid=props.domain_sid,
            ldap_root_dn=props.ldap_root_dn,
            ldap_search_password=props.ldap_search_password,
            ldap_server_ip=props.ldap_server_ip,
            linux_update_server_ip=props.linux_update_server_ip,
            storage_account_userdata_name=props.storage_account_userdata_name,
            storage_account_securedata_name=props.storage_account_securedata_name,
            security_group_name=props.security_group_name,
        ).apply(lambda kwargs: self.read_cloudinit(**kwargs))

        # Deploy a variable number of VMs depending on the input parameters
        vms = [
            VMComponent(
                replace_separators(f"sre_{sre_name}_vm_{vm_name}", "_"),
                LinuxVMProps(
                    admin_password=props.admin_password,
                    admin_username=props.admin_username,
                    b64cloudinit=b64cloudinit,
                    ip_address_private=props.vm_ip_addresses[vm_idx],
                    location=props.location,
                    log_analytics_workspace_id=props.log_analytics_workspace_id,
                    log_analytics_workspace_key=props.log_analytics_workspace_key,
                    resource_group_name=resource_group.name,
                    subnet_name=props.subnet_research_desktops_name,
                    virtual_network_name=props.virtual_network_name,
                    virtual_network_resource_group_name=props.virtual_network_resource_group_name,
                    vm_name=replace_separators(f"sre-{sre_name}-vm-{vm_name}", "-"),
                    vm_size=vm_size,
                ),
                opts=child_opts,
            )
            for vm_idx, vm_name, vm_size in props.vm_details
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
            "security_group_name": props.security_group_name,
            "vm_outputs": vm_outputs,
        }

    def read_cloudinit(
        self,
        domain_sid: str,
        ldap_root_dn: str,
        ldap_search_password: str,
        ldap_server_ip: str,
        linux_update_server_ip: str,
        storage_account_userdata_name: str,
        storage_account_securedata_name: str,
        security_group_name: str,
    ) -> str:
        resources_path = (
            pathlib.Path(__file__).parent.parent.parent
            / "resources"
            / "secure_research_desktop"
        )
        with open(
            resources_path / "srd.cloud_init.mustache.yaml", "r", encoding="utf-8"
        ) as f_cloudinit:
            mustache_values = {
                "domain_sid": domain_sid,
                "ldap_root_dn": ldap_root_dn,
                "ldap_search_password": ldap_search_password,
                "ldap_server_ip": ldap_server_ip,
                "ldap_sre_security_group": security_group_name,
                "linux_update_server_ip": linux_update_server_ip,
                "storage_account_userdata_name": storage_account_userdata_name,
                "storage_account_securedata_name": storage_account_securedata_name,
            }
            cloudinit = chevron.render(f_cloudinit, mustache_values)
            return b64encode(cloudinit)
