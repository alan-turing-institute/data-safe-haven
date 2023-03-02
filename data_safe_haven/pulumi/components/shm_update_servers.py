"""Pulumi component for SHM monitoring"""
# Standard library import
import pathlib
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network

# Local imports
from data_safe_haven.helpers import b64encode
from data_safe_haven.pulumi.transformations import (
    get_available_ips_from_subnet,
    get_name_from_subnet,
)
from .virtual_machine import VMComponent, LinuxVMProps


class SHMUpdateServersProps:
    """Properties for SHMUpdateServersComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        location: Input[str],
        resource_group_name: Input[str],
        subnet: Input[network.GetSubnetResult],
        virtual_network_name: Input[str],
        virtual_network_resource_group_name: Input[str],
    ) -> None:
        self.admin_password = Output.secret(admin_password)
        self.admin_username = "dshadmin"
        available_ip_addresses = Output.from_input(subnet).apply(
            get_available_ips_from_subnet
        )
        self.ip_address_linux = available_ip_addresses.apply(lambda ips: ips[0])
        self.location = location
        self.resource_group_name = resource_group_name
        self.subnet_name = Output.from_input(subnet).apply(get_name_from_subnet)
        self.virtual_network_name = virtual_network_name
        self.virtual_network_resource_group_name = virtual_network_resource_group_name


class SHMUpdateServersComponent(ComponentResource):
    """Deploy SHM update servers with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        shm_name: str,
        props: SHMUpdateServersProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:shm:SHMUpdateServersComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Load cloud-init file
        b64cloudinit = self.read_cloudinit()
        vm_name = f"shm-{shm_name}-vm-linux-updates"
        VMComponent(
            vm_name,
            LinuxVMProps(
                admin_password=props.admin_password,
                admin_username=props.admin_username,
                b64cloudinit=b64cloudinit,
                ip_address_private=props.ip_address_linux,
                location=props.location,
                resource_group_name=props.resource_group_name,
                subnet_name=props.subnet_name,
                virtual_network_name=props.virtual_network_name,
                virtual_network_resource_group_name=props.virtual_network_resource_group_name,
                vm_name=vm_name,
                vm_size="Standard_F1s",
            ),
            opts=child_opts,
        )

        # Register exports
        self.exports = {"ip_address_linux": props.ip_address_linux}

    def read_cloudinit(
        self,
    ) -> str:
        resources_path = (
            pathlib.Path(__file__).parent.parent.parent / "resources" / "update_servers"
        )
        with open(
            resources_path / "update_server_linux.cloud_init.yaml",
            "r",
            encoding="utf-8",
        ) as f_cloudinit:
            cloudinit = f_cloudinit.read()
        return b64encode(cloudinit)
