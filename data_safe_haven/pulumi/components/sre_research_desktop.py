# Standard library imports
import pathlib
from typing import Any, Dict, List, Optional

# Third party imports
import chevron
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

# Local imports
from data_safe_haven.exceptions import DataSafeHavenPulumiException
from data_safe_haven.helpers import b64encode, replace_separators
from data_safe_haven.pulumi.transformations import (
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
        security_group_name: Input[str],
        subnet_research_desktops: Input[network.GetSubnetResult],
        virtual_network_resource_group: Input[resources.ResourceGroup],
        virtual_network: Input[network.VirtualNetwork],
        vm_details: Input[Dict[str, Dict[str, str]]],
    ):
        self.admin_password = Output.secret(admin_password)
        self.admin_username = "dshadmin"
        self.domain_sid = domain_sid
        self.ldap_root_dn = ldap_root_dn
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.linux_update_server_ip = linux_update_server_ip
        self.location = location
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
        vm_lists = Output.from_input(vm_details).apply(
            lambda d: [
                (
                    name,
                    details["sku"],
                )
                for name, details in d.items()
            ]
        )
        self.vm_names = vm_lists.apply(lambda l: [t[0] for t in l])
        self.vm_sizes = vm_lists.apply(lambda l: [t[1] for t in l])

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
            security_group_name=props.security_group_name,
        ).apply(lambda kwargs: self.read_cloudinit(**kwargs))

        # Deploy a variable number of VMs depending on the input parameters
        # We separate the all() and apply() in order to provide a type-hint
        vm_details: Output[Dict[str, List[str]]] = Output.all(
            vm_ip_addresses=props.vm_ip_addresses,
            vm_names=props.vm_names,
            vm_sizes=props.vm_sizes,
        )
        # Note that creating resources inside an .apply() is discouraged but not
        # forbidden. This is the one way to create one resource for each entry in
        # an Output[Sequence]. See https://github.com/pulumi/pulumi/issues/3849.
        vms = vm_details.apply(
            lambda kwargs: [
                VMComponent(
                    replace_separators(f"sre-{sre_name}-vm-{vm_name}", "-"),
                    LinuxVMProps(
                        admin_password=props.admin_password,
                        admin_username=props.admin_username,
                        b64cloudinit=b64cloudinit,
                        ip_address_private=str(vm_ip_address),
                        location=props.location,
                        resource_group_name=resource_group.name,
                        subnet_name=props.subnet_research_desktops_name,
                        virtual_network_name=props.virtual_network_name,
                        virtual_network_resource_group_name=props.virtual_network_resource_group_name,
                        vm_name=str(vm_name),
                        vm_size=str(vm_size),
                    ),
                    opts=child_opts,
                )
                for vm_ip_address, vm_name, vm_size in zip(
                    kwargs["vm_ip_addresses"], kwargs["vm_names"], kwargs["vm_sizes"]
                )
            ]
        )
        # Get details for each deployed VM
        vm_outputs = vms.apply(
            lambda vms: [
                Output.all(vm.ip_address_private, vm.vm_name, vm.vm_size).apply(
                    lambda args: {
                        "ip_address": str(args[0]),
                        "name": str(args[1]),
                        "sku": str(args[2]),
                    }
                )
                for vm in vms
            ]
        )

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
            }
            cloudinit = chevron.render(f_cloudinit, mustache_values)
            return b64encode(cloudinit)
