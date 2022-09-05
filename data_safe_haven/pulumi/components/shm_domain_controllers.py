# Third party imports
from pulumi import ComponentResource, Input, ResourceOptions, Output
from pulumi_azure_native import network

# Local
from .vms import VMComponent, WindowsVMProps


class SHMDomainControllersProps:
    """Properties for SHMDomainControllersComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        ip_address_private: Input[str],
        location: Input[str],
        resource_group_name: Input[str],
        subnet_name: Input[str],
        virtual_network_name: Input[str],
        virtual_network_resource_group_name: Input[str],
    ):
        self.admin_password = admin_password
        self.ip_address_private = ip_address_private
        self.location = location
        self.resource_group_name = resource_group_name
        self.subnet_name = subnet_name
        self.virtual_network_name = virtual_network_name
        self.virtual_network_resource_group_name = virtual_network_resource_group_name


class SHMDomainControllersComponent(ComponentResource):
    """Deploy SHM secrets with Pulumi"""

    def __init__(
        self, name: str, props: SHMDomainControllersProps, opts: ResourceOptions = None
    ):
        super().__init__(
            "dsh:shm_domain_controllers:SHMDomainControllersComponent", name, {}, opts
        )
        child_opts = ResourceOptions(parent=self)

        primary_domain_controller = VMComponent(
            "primary_domain_controller",
            WindowsVMProps(
                admin_password=props.admin_password,
                ip_address_private=props.ip_address_private,
                location=props.location,
                resource_group_name=props.resource_group_name,
                subnet_name=props.subnet_name,
                virtual_network_name=props.virtual_network_name,
                virtual_network_resource_group_name=props.virtual_network_resource_group_name,
                vm_name=f"shm-{self._name[:7]}-dc1",
                vm_size="Standard_DS2_v2",
            ),
            opts=child_opts,
        )

        # Register outputs
        self.resource_group_name = Output.from_input(props.resource_group_name)
