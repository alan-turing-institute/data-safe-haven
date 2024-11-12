"""Pulumi component for virtual machines"""

from collections.abc import Mapping
from typing import Any

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import compute, insights, maintenance, network

from data_safe_haven.functions import replace_separators


class VMComponentProps:
    """Properties for WindowsVMComponent"""

    image_reference_args: compute.ImageReferenceArgs | None
    azure_monitor_extension_name: str
    azure_monitor_extension_version: str
    os_profile_args: compute.OSProfileArgs | None

    def __init__(
        self,
        admin_password: Input[str],
        data_collection_rule_id: Input[str],
        data_collection_endpoint_id: Input[str],
        ip_address_private: Input[str],
        location: Input[str],
        resource_group_name: Input[str],
        subnet_name: Input[str],
        virtual_network_name: Input[str],
        virtual_network_resource_group_name: Input[str],
        vm_name: Input[str],
        vm_size: Input[str],
        admin_username: Input[str] | None = None,
        ip_address_public: Input[bool] | None = None,
        maintenance_configuration_id: Input[str] | None = None,
    ) -> None:
        self.admin_password = admin_password
        self.admin_username = admin_username if admin_username else "dshvmadmin"
        self.data_collection_rule_id = data_collection_rule_id
        self.data_collection_rule_name = Output.from_input(
            data_collection_rule_id
        ).apply(lambda rule_id: str(rule_id).split("/")[-1])
        self.data_collection_endpoint_id = data_collection_endpoint_id
        self.image_reference_args = None
        self.ip_address_private = ip_address_private
        self.ip_address_public = ip_address_public
        self.location = location
        self.maintenance_configuration_id = maintenance_configuration_id
        self.os_profile_args = None
        self.resource_group_name = resource_group_name
        self.subnet_name = subnet_name
        self.virtual_network_name = virtual_network_name
        self.virtual_network_resource_group_name = virtual_network_resource_group_name
        self.vm_name = vm_name
        self.vm_name_underscored = Output.from_input(vm_name).apply(
            lambda n: replace_separators(n, "_")
        )
        self.vm_size = vm_size

    @property
    def image_reference(self) -> compute.ImageReferenceArgs | None:
        return self.image_reference_args

    @property
    def os_profile(self) -> compute.OSProfileArgs | None:
        return self.os_profile_args


class LinuxVMComponentProps(VMComponentProps):
    """Properties for LinuxVMComponent"""

    def __init__(
        self,
        b64cloudinit: Input[str],
        *args: Any,
        **kwargs: Any,
    ):
        super().__init__(*args, **kwargs)
        self.image_reference_args = compute.ImageReferenceArgs(
            offer="0001-com-ubuntu-server-jammy",
            publisher="Canonical",
            sku="22_04-LTS-gen2",
            version="latest",
        )
        self.os_profile_args = compute.OSProfileArgs(
            admin_password=self.admin_password,
            admin_username=self.admin_username,
            computer_name=Output.from_input(self.vm_name).apply(lambda n: n[:64]),
            custom_data=Output.secret(b64cloudinit),
            linux_configuration=compute.LinuxConfigurationArgs(
                patch_settings=compute.LinuxPatchSettingsArgs(
                    assessment_mode=compute.LinuxPatchAssessmentMode.AUTOMATIC_BY_PLATFORM,
                    patch_mode=compute.LinuxVMGuestPatchMode.AUTOMATIC_BY_PLATFORM,
                    automatic_by_platform_settings=compute.LinuxVMGuestPatchAutomaticByPlatformSettingsArgs(
                        bypass_platform_safety_checks_on_user_schedule=True,
                        reboot_setting=compute.LinuxVMGuestPatchAutomaticByPlatformRebootSetting.IF_REQUIRED,
                    ),
                ),
                provision_vm_agent=True,
            ),
        )
        self.azure_monitor_extension_name = "AzureMonitorLinuxAgent"
        self.azure_monitor_extension_version = "1.0"


class VMComponent(ComponentResource):
    """Deploy SHM secrets with Pulumi"""

    def __init__(
        self,
        name: str,
        props: VMComponentProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ):
        super().__init__("dsh:common:VMComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}
        name_underscored = replace_separators(self._name, "_")

        # Retrieve existing resources
        subnet = network.get_subnet_output(
            subnet_name=props.subnet_name,
            resource_group_name=props.virtual_network_resource_group_name,
            virtual_network_name=props.virtual_network_name,
        )

        # Define public IP address if relevant
        network_interface_ip_params: dict[str, Any] = {}
        if props.ip_address_public:
            public_ip = network.PublicIPAddress(
                f"{name_underscored}_public_ip",
                location=props.location,
                public_ip_address_name=Output.concat(props.vm_name, "-public-ip"),
                public_ip_allocation_method="Static",
                resource_group_name=props.resource_group_name,
                sku=network.PublicIPAddressSkuArgs(
                    name=network.PublicIPAddressSkuName.STANDARD
                ),
                opts=child_opts,
                tags=child_tags,
            )
            network_interface_ip_params["public_ip_address"] = (
                network.PublicIPAddressArgs(id=public_ip.id)
            )

        # Define network card
        network_interface = network.NetworkInterface(
            f"{name_underscored}_network_interface",
            enable_accelerated_networking=True,
            ip_configurations=[
                network.NetworkInterfaceIPConfigurationArgs(
                    name=props.vm_name_underscored.apply(
                        lambda n: replace_separators(f"ipconfig{n}", "")
                    ),
                    private_ip_address=props.ip_address_private,
                    private_ip_allocation_method=network.IPAllocationMethod.STATIC,
                    subnet=network.SubnetArgs(id=subnet.id),
                    **network_interface_ip_params,
                )
            ],
            location=props.location,
            network_interface_name=Output.concat(props.vm_name, "-nic"),
            resource_group_name=props.resource_group_name,
            opts=child_opts,
            tags=child_tags,
        )

        # Define virtual machine
        virtual_machine = compute.VirtualMachine(
            name_underscored,
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
                    name=Output.concat(props.vm_name, "-osdisk"),
                ),
            ),
            vm_name=props.vm_name,
            identity=compute.VirtualMachineIdentityArgs(
                type=compute.ResourceIdentityType.SYSTEM_ASSIGNED,
            ),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    delete_before_replace=True, replace_on_changes=["os_profile"]
                ),
            ),
            tags=child_tags,
        )

        # Register with Log Analytics workspace
        compute.VirtualMachineExtension(
            f"{name_underscored}_azure_monitor_extension",
            auto_upgrade_minor_version=True,
            enable_automatic_upgrade=True,
            location=props.location,
            publisher="Microsoft.Azure.Monitor",
            resource_group_name=props.resource_group_name,
            type=props.azure_monitor_extension_name,
            type_handler_version=props.azure_monitor_extension_version,
            vm_extension_name=props.azure_monitor_extension_name,
            vm_name=virtual_machine.name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=virtual_machine),
            ),
            tags=child_tags,
        )

        # Register with maintenance configuration
        maintenance.ConfigurationAssignment(
            f"{name_underscored}_configuration_assignment",
            configuration_assignment_name=Output.concat(
                props.vm_name, "-maintenance-configuration"
            ),
            location=props.location,
            maintenance_configuration_id=props.maintenance_configuration_id,
            provider_name="Microsoft.Compute",
            resource_group_name=props.resource_group_name,
            resource_name_=virtual_machine.name,
            resource_type="VirtualMachines",
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=virtual_machine),
            ),
        )

        # Register with data collection rule
        insights.DataCollectionRuleAssociation(
            f"{name_underscored}_dcra_to_dcr",
            association_name=Output.concat(
                props.data_collection_rule_name, "-association"  # this name is required
            ),
            data_collection_rule_id=props.data_collection_rule_id,
            resource_uri=virtual_machine.id,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=virtual_machine),
            ),
        )

        # Register with data collection endpoint
        insights.DataCollectionRuleAssociation(
            f"{name_underscored}_dcra_to_dce",
            association_name="configurationAccessEndpoint",  # this name is required
            data_collection_endpoint_id=props.data_collection_endpoint_id,
            resource_uri=virtual_machine.id,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=virtual_machine),
            ),
        )

        # Register outputs
        self.ip_address_private: Output[str] = Output.from_input(
            props.ip_address_private
        )
        self.resource_group_name: Output[str] = Output.from_input(
            props.resource_group_name
        )
        self.vm_name: Output[str] = virtual_machine.name
        self.vm_size: Output[str] = Output.from_input(props.vm_size)
