# Standard library imports
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, ResourceOptions, Output
from pulumi_azure_native import compute, network


class VMProps:
    """Properties for WindowsVMComponent"""

    def __init__(
        self,
        ip_address_private: Input[str],
        location: Input[str],
        resource_group_name: Input[str],
        subnet_name: Input[str],
        virtual_network_name: Input[str],
        virtual_network_resource_group_name: Input[str],
        vm_name: Input[str],
        vm_size: Input[str],
        ip_address_public: Optional[Input[str]] = None,
    ):
        self.image_reference_args = None
        self.ip_address_private = ip_address_private
        self.ip_address_public = ip_address_public
        self.location = location
        self.os_profile_args = None
        self.resource_group_name = resource_group_name
        self.subnet_name = subnet_name
        self.virtual_network_name = virtual_network_name
        self.virtual_network_resource_group_name = virtual_network_resource_group_name
        self.vm_name = vm_name
        self.vm_name_underscored = vm_name.replace("-", "_")
        self.vm_size = vm_size

    @property
    def os_profile(self) -> compute.OSProfileArgs:
        return self.os_profile_args

    @property
    def image_reference(self) -> compute.ImageReferenceArgs:
        return self.image_reference_args


class WindowsVMProps(VMProps):
    """Properties for WindowsVMComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        *args,
        **kwargs,
    ):
        super().__init__(*args, **kwargs)
        self.os_profile_args = compute.OSProfileArgs(
            admin_password=admin_password,
            admin_username="dshadmin",
            computer_name=self.vm_name,
            windows_configuration=compute.WindowsConfigurationArgs(
                enable_automatic_updates=True,
                patch_settings=compute.PatchSettingsArgs(
                    patch_mode="AutomaticByPlatform",
                ),
                provision_vm_agent=True,
            ),
        )
        self.image_reference_args = compute.ImageReferenceArgs(
            offer="WindowsServer",
            publisher="MicrosoftWindowsServer",
            sku="2022-Datacenter",
            version="latest",
        )


class LinuxVMProps(VMProps):
    """Properties for LinuxVMComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        b64cloudinit: Input[str],
        *args,
        **kwargs,
    ):
        super().__init__(*args, **kwargs)
        self.os_profile_args = compute.OSProfileArgs(
            admin_password=admin_password,
            admin_username="dshadmin",
            computer_name=self.vm_name,
            custom_data=Output.secret(b64cloudinit),
            linux_configuration=compute.LinuxConfigurationArgs(
                patch_settings=compute.LinuxPatchSettingsArgs(
                    assessment_mode="AutomaticByPlatform",
                ),
                provision_vm_agent=True,
            ),
        )
        self.image_reference_args = compute.ImageReferenceArgs(
            offer="0001-com-ubuntu-server-focal",
            publisher="Canonical",
            sku="20_04-LTS",
            version="latest",
        )


class VMComponent(ComponentResource):
    """Deploy SHM secrets with Pulumi"""

    def __init__(self, name: str, props: VMProps, opts: ResourceOptions = None):
        super().__init__("dsh:vms:VMComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Retrieve existing resources
        subnet = network.get_subnet_output(
            subnet_name=props.subnet_name,
            resource_group_name=props.virtual_network_resource_group_name,
            virtual_network_name=props.virtual_network_name,
        )

        # Define public IP address if relevant
        network_interface_ip_params = {}
        if props.ip_address_public:
            public_ip = network.PublicIPAddress(
                f"public_ip_{props.vm_name_underscored}",
                public_ip_address_name=f"{props.vm_name}-public-ip",
                public_ip_allocation_method="Static",
                resource_group_name=props.resource_group_name,
                sku=network.PublicIPAddressSkuArgs(name="Standard"),
                opts=opts,
            )
            network_interface_ip_params[
                "public_ip_address"
            ] = network.PublicIPAddressArgs(id=public_ip.id)

        # Define network card
        network_interface = network.NetworkInterface(
            f"network_interface_{props.vm_name_underscored}",
            enable_accelerated_networking=True,
            ip_configurations=[
                network.NetworkInterfaceIPConfigurationArgs(
                    name="ipconfigsecureresearchdesktop",
                    private_ip_address=props.ip_address_private,
                    subnet=network.SubnetArgs(id=subnet.id),
                    **network_interface_ip_params,
                )
            ],
            network_interface_name=f"{props.vm_name}-nic",
            resource_group_name=props.resource_group_name,
            opts=opts,
        )

        # Define virtual machine
        virtual_machine = compute.VirtualMachine(
            "virtualMachine",
            hardware_profile=compute.HardwareProfileArgs(
                vm_size=props.vm_size,
            ),
            location=props.location,
            network_profile=compute.NetworkProfileArgs(
                network_interfaces=[
                    compute.NetworkInterfaceReferenceArgs(
                        id=network_interface.id,
                        primary=True,
                    )
                ],
            ),
            os_profile=props.os_profile,
            resource_group_name=props.resource_group_name,
            storage_profile=compute.StorageProfileArgs(
                image_reference=props.image_reference,
                os_disk=compute.OSDiskArgs(
                    caching="ReadWrite",
                    create_option="FromImage",
                    delete_option="Delete",
                    managed_disk=compute.ManagedDiskParametersArgs(
                        storage_account_type="Premium_LRS",
                    ),
                    name=f"{props.vm_name}-osdisk",
                ),
            ),
            vm_name=props.vm_name,
            opts=ResourceOptions(
                delete_before_replace=True, replace_on_changes=["os_profile"]
            ),
        )
        # Register outputs
        self.resource_group_name = Output.from_input(props.resource_group_name)
        self.virtual_machine = virtual_machine
