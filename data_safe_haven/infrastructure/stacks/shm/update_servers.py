"""Pulumi component for SHM monitoring"""
import pathlib

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network

from data_safe_haven.functions import b64encode
from data_safe_haven.infrastructure.common import (
    get_available_ips_from_subnet,
    get_name_from_subnet,
)
from data_safe_haven.infrastructure.components import (
    LinuxVMComponentProps,
    VMComponent,
)


class SHMUpdateServersProps:
    """Properties for SHMUpdateServersComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        location: Input[str],
        log_analytics_workspace_id: Input[str],
        log_analytics_workspace_key: Input[str],
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
        self.log_analytics_workspace_id = log_analytics_workspace_id
        self.log_analytics_workspace_key = log_analytics_workspace_key
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
        props: SHMUpdateServersProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:shm:UpdateServersComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        # Load cloud-init file
        b64cloudinit = self.read_cloudinit()
        vm_name = f"{stack_name}-vm-linux-updates"
        VMComponent(
            vm_name,
            LinuxVMComponentProps(
                admin_password=props.admin_password,
                admin_username=props.admin_username,
                b64cloudinit=b64cloudinit,
                ip_address_private=props.ip_address_linux,
                location=props.location,
                log_analytics_workspace_id=props.log_analytics_workspace_id,
                log_analytics_workspace_key=props.log_analytics_workspace_key,
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
            encoding="utf-8",
        ) as f_cloudinit:
            cloudinit = f_cloudinit.read()
        return b64encode(cloudinit)
