"""Pulumi component for virtual machines"""
# Standard library imports
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import compute, network


class VMProps:
    """Properties for WindowsVMComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        ip_address_private: Input[str],
        location: Input[str],
        resource_group_name: Input[str],
        subnet_name: Input[str],
        virtual_network_name: Input[str],
        virtual_network_resource_group_name: Input[str],
        vm_name: Input[str],
        vm_size: Input[str],
        admin_username: Optional[Input[str]] = None,
        ip_address_public: Optional[Input[bool]] = None,
    ):
        self.admin_password = admin_password
        self.admin_username = admin_username if admin_username else "dshvmadmin"
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
        self.vm_name_underscored = Output.from_input(vm_name).apply(
            lambda n: n.replace("-", "_")
        )
        self.vm_size = vm_size

    @property
    def os_profile(self) -> compute.OSProfileArgs | None:
        return self.os_profile_args

    @property
    def image_reference(self) -> compute.ImageReferenceArgs | None:
        return self.image_reference_args


class WindowsVMProps(VMProps):
    """Properties for WindowsVMComponent"""

    def __init__(
        self,
        *args,
        **kwargs,
    ):
        super().__init__(*args, **kwargs)
        self.os_profile_args = compute.OSProfileArgs(
            admin_password=self.admin_password,
            admin_username=self.admin_username,
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
        b64cloudinit: Input[str],
        *args,
        **kwargs,
    ):
        super().__init__(*args, **kwargs)
        self.os_profile_args = compute.OSProfileArgs(
            admin_password=self.admin_password,
            admin_username=self.admin_username,
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

    def __init__(
        self, name: str, props: VMProps, opts: Optional[ResourceOptions] = None
    ):
        super().__init__("dsh:common:VMComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

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
                f"{self._name}_public_ip",
                public_ip_address_name=f"{props.vm_name}-public-ip",
                public_ip_allocation_method="Static",
                resource_group_name=props.resource_group_name,
                sku=network.PublicIPAddressSkuArgs(
                    name=network.PublicIPAddressSkuName.STANDARD
                ),
                opts=child_opts,
            )
            network_interface_ip_params[
                "public_ip_address"
            ] = network.PublicIPAddressArgs(id=public_ip.id)

        # Define network card
        network_interface = network.NetworkInterface(
            f"{self._name}_network_interface",
            enable_accelerated_networking=True,
            ip_configurations=[
                network.NetworkInterfaceIPConfigurationArgs(
                    name=props.vm_name_underscored.apply(lambda n: f"ipconfig{n}".replace("_", "")),
                    private_ip_address=props.ip_address_private,
                    private_ip_allocation_method=network.IPAllocationMethod.STATIC,
                    subnet=network.SubnetArgs(id=subnet.id),
                    **network_interface_ip_params,
                )
            ],
            network_interface_name=f"{props.vm_name}-nic",
            resource_group_name=props.resource_group_name,
            opts=child_opts,
        )

        # Define virtual machine
        virtual_machine = compute.VirtualMachine(
            self._name,
            diagnostics_profile=compute.DiagnosticsProfileArgs(
                boot_diagnostics=compute.BootDiagnosticsArgs(enabled=True)
            ),
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
                    caching=compute.CachingTypes.READ_WRITE,
                    create_option=compute.DiskCreateOptionTypes.FROM_IMAGE,
                    delete_option=compute.DiskDeleteOptionTypes.DELETE,
                    managed_disk=compute.ManagedDiskParametersArgs(
                        storage_account_type=compute.StorageAccountTypes.PREMIUM_LRS,
                    ),
                    name=f"{props.vm_name}-osdisk",
                ),
            ),
            vm_name=props.vm_name,
            opts=ResourceOptions.merge(
                ResourceOptions(
                    delete_before_replace=True, replace_on_changes=["os_profile"]
                ),
                child_opts,
            ),
        )
        # Register outputs
        self.ip_address_private = Output.from_input(props.ip_address_private)
        self.resource_group_name = Output.from_input(props.resource_group_name)
        self.vm_name = virtual_machine.name
