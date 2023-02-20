# Standard library imports
import pathlib
from typing import Dict, List, Optional, Sequence, cast

# Third party imports
import chevron
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

# Local imports
from data_safe_haven.external.interface import AzureIPv4Range
from data_safe_haven.helpers import b64encode, replace_separators
from data_safe_haven.pulumi.transformations import (
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
            lambda args: self.get_ip_addresses(
                cast(network.GetSubnetResult, args[0]), len(cast(List[str], args[1]))
            )
        )
        vm_lists = Output.from_input(vm_details).apply(
            lambda d: [(k, v["sku"]) for k, v in d.items()]
        )
        self.vm_names = vm_lists.apply(lambda l: [t[0] for t in l])
        self.vm_sizes = vm_lists.apply(lambda l: [t[1] for t in l])

    def get_ip_addresses(
        self, subnet: network.GetSubnetResult, number: int
    ) -> List[str]:
        if not subnet.address_prefix:
            return []
        return [
            str(ip)
            for ip in AzureIPv4Range.from_cidr(subnet.address_prefix).available()
        ][:number]


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
            security_group_name=props.security_group_name,
        ).apply(lambda kwargs: self.read_cloudinit(**kwargs))

        # Deploy a variable number of VMs depending on the input parameters
        # Note that deploying inside an apply is advised against but not forbidden
        Output.all(
            vm_ip_addresses=props.vm_ip_addresses,
            vm_names=props.vm_names,
            vm_sizes=props.vm_sizes,
        ).apply(
            lambda kwargs: (
                VMComponent(
                    replace_separators(f"sre-{sre_name}-vm-{vm_name}", "-"),
                    LinuxVMProps(
                        admin_password=props.admin_password,
                        admin_username=props.admin_username,
                        b64cloudinit=b64cloudinit,
                        ip_address_private=vm_ip_address,
                        location=props.location,
                        resource_group_name=resource_group.name,
                        subnet_name=props.subnet_research_desktops_name,
                        virtual_network_name=props.virtual_network_name,
                        virtual_network_resource_group_name=props.virtual_network_resource_group_name,
                        vm_name=vm_name,
                        vm_size=vm_size,
                    ),
                    opts=child_opts,
                )
                for vm_ip_address, vm_name, vm_size in zip(
                    kwargs["vm_ip_addresses"], kwargs["vm_names"], kwargs["vm_sizes"]
                )
            )
        )

        # Register outputs
        self.resource_group = resource_group

        # Register exports
        self.exports = {
            "vm_ip_addresses": props.vm_ip_addresses,
            "vm_names": props.vm_names,
        }

    def deploy_vms(
        self,
        admin_password: str,
        admin_username: str,
        b64cloudinit: str,
        location: str,
        resource_group_name: str,
        sre_name: str,
        subnet_research_desktops_name: str,
        virtual_network_name: str,
        virtual_network_resource_group_name: str,
        vm_ip_addresses: Sequence[str],
        vm_names: Sequence[str],
        vm_sizes: Sequence[str],
        child_opts: ResourceOptions,
    ) -> None:
        # Deploy as many VMs as requested
        for vm_ip_address, vm_name, vm_size in zip(vm_ip_addresses, vm_names, vm_sizes):
            VMComponent(
                replace_separators(f"sre-{sre_name}-{vm_name}", "-"),
                LinuxVMProps(
                    admin_password=admin_password,
                    admin_username=admin_username,
                    b64cloudinit=b64cloudinit,
                    ip_address_private=vm_ip_address,
                    location=location,
                    resource_group_name=resource_group_name,
                    subnet_name=subnet_research_desktops_name,
                    virtual_network_name=virtual_network_name,
                    virtual_network_resource_group_name=virtual_network_resource_group_name,
                    vm_name=vm_name,
                    vm_size=vm_size,
                ),
                opts=child_opts,
            )

    def read_cloudinit(
        self,
        domain_sid: str,
        ldap_root_dn: str,
        ldap_search_password: str,
        ldap_server_ip: str,
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
            }
            cloudinit = chevron.render(f_cloudinit, mustache_values)
            return b64encode(cloudinit)
