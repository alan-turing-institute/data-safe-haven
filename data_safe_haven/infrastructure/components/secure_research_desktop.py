# Standard library imports
import base64
import pathlib
from typing import Optional, Sequence

# Third party imports
import chevron
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import compute, network


class SecureResearchDesktopProps:
    """Properties for SecureResearchDesktopComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        ip_addresses: Input[Sequence[str]],
        ldap_group_base_dn: Input[str],
        ldap_root_dn: Input[str],
        ldap_search_password: Input[str],
        ldap_server_ip: Input[str],
        ldap_user_base_dn: Input[str],
        resource_group_name: Input[str],
        virtual_network: Input[network.VirtualNetwork],
        virtual_network_resource_group_name: Input[str],
        vm_sizes: Sequence[Input[str]],
        subnet_name: Optional[Input[str]] = "SecureResearchDesktopSubnet",
    ):
        self.admin_password = admin_password
        self.ip_addresses = ip_addresses
        self.ldap_group_base_dn = ldap_group_base_dn
        self.ldap_root_dn = ldap_root_dn
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.ldap_user_base_dn = ldap_user_base_dn
        self.resource_group_name = resource_group_name
        self.subnet_name = subnet_name
        self.virtual_network = virtual_network
        self.virtual_network_resource_group_name = virtual_network_resource_group_name
        self.vm_short_names = Output.from_input(vm_sizes).apply(
            lambda vm_sizes: self.construct_names(vm_sizes)
        )
        self.vm_sizes = vm_sizes

    def construct_names(self, vm_sizes):
        """Construct VM names from a list of sizes"""
        vm_names = []
        idx_cpu, idx_gpu = 0, 0
        for vm_size in vm_sizes:
            if vm_size.startswith("Standard_N"):
                vm_names.append(f"srd-gpu-{idx_gpu:02d}")
                idx_gpu = idx_gpu + 1
            else:
                vm_names.append(f"srd-cpu-{idx_cpu:02d}")
                idx_cpu = idx_cpu + 1
        return vm_names


class SecureResearchDesktopComponent(ComponentResource):
    """Deploy secure research desktops with Pulumi"""

    def __init__(
        self, name: str, props: SecureResearchDesktopProps, opts: ResourceOptions = None
    ):
        super().__init__("dsh:srd:SecureResearchDesktopComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Deploy a variable number of VMs depending on the input parameters
        Output.all(
            admin_password=props.admin_password,
            ip_addresses=props.ip_addresses,
            ldap_group_base_dn=props.ldap_group_base_dn,
            ldap_root_dn=props.ldap_root_dn,
            ldap_search_password=props.ldap_search_password,
            ldap_server_ip=props.ldap_server_ip,
            ldap_user_base_dn=props.ldap_user_base_dn,
            vm_short_names=props.vm_short_names,
            vm_sizes=props.vm_sizes,
        ).apply(
            lambda args: self.deploy(
                admin_password=args["admin_password"],
                ip_addresses=args["ip_addresses"],
                ldap_group_base_dn=args["ldap_group_base_dn"],
                ldap_root_dn=args["ldap_root_dn"],
                ldap_search_password=args["ldap_search_password"],
                ldap_server_ip=args["ldap_server_ip"],
                ldap_user_base_dn=args["ldap_user_base_dn"],
                vm_short_names=args["vm_short_names"],
                vm_sizes=args["vm_sizes"],
                props=props,
                opts=child_opts,
            )
        )

        # Register outputs
        self.resource_group_name = Output.from_input(props.resource_group_name)
        self.vm_details = Output.all(
            vm_short_names=props.vm_short_names, ip_addresses=props.ip_addresses
        ).apply(lambda args: list(zip(args["vm_short_names"], args["ip_addresses"])))

    def deploy(
        self,
        admin_password: str,
        ip_addresses: Sequence[str],
        ldap_group_base_dn: str,
        ldap_root_dn: str,
        ldap_search_password: str,
        ldap_server_ip: str,
        ldap_user_base_dn: str,
        vm_short_names: Sequence[str],
        vm_sizes: Sequence[str],
        props: SecureResearchDesktopProps,
        opts: ResourceOptions = None,
    ):
        # Retrieve existing resources
        snet_secure_research_desktop = network.get_subnet_output(
            subnet_name=props.subnet_name,
            resource_group_name=props.virtual_network_resource_group_name,
            virtual_network_name=props.virtual_network.name,
        )

        # Load cloud-init file
        resources_path = (
            pathlib.Path(__file__).parent.parent.parent
            / "resources"
            / "secure_research_desktop"
        )
        with open(resources_path / "srd.cloud_init.mustache.yaml", "r") as f_cloudinit:
            mustache_values = {
                "ldap_group_base_dn": ldap_group_base_dn,
                "ldap_root_dn": ldap_root_dn,
                "ldap_search_password": ldap_search_password,
                "ldap_server_ip": ldap_server_ip,
                "ldap_user_base_dn": ldap_user_base_dn,
            }
            cloudinit = chevron.render(f_cloudinit, mustache_values)
            b64cloudinit = base64.b64encode(cloudinit.encode("utf-8")).decode()

        # Deploy secure research desktops
        for vm_short_name, vm_size, ip_address in zip(
            vm_short_names, vm_sizes, ip_addresses
        ):
            vm_name = f"vm-{self._name}-{vm_short_name}"
            vm_name_underscored = vm_name.replace("-", "_")

            # Define public IP address
            public_ip = network.PublicIPAddress(
                f"public_ip_{vm_name_underscored}",
                public_ip_address_name=f"{vm_name}-public-ip",
                public_ip_allocation_method="Static",
                resource_group_name=props.resource_group_name,
                sku=network.PublicIPAddressSkuArgs(name="Standard"),
                opts=opts,
            )
            network_interface = network.NetworkInterface(
                f"network_interface_{vm_name_underscored}",
                enable_accelerated_networking=True,
                ip_configurations=[
                    network.NetworkInterfaceIPConfigurationArgs(
                        name="ipconfigsecureresearchdesktop",
                        public_ip_address=network.PublicIPAddressArgs(id=public_ip.id),
                        private_ip_address=ip_address,
                        subnet=network.SubnetArgs(id=snet_secure_research_desktop.id),
                    )
                ],
                network_interface_name=f"{vm_name_underscored}-nic",
                resource_group_name=props.resource_group_name,
                opts=opts,
            )
            virtual_machine = compute.VirtualMachine(
                f"virtual_machine_{vm_name_underscored}",
                hardware_profile=compute.HardwareProfileArgs(
                    vm_size=vm_size,
                ),
                network_profile=compute.NetworkProfileArgs(
                    network_interfaces=[
                        compute.NetworkInterfaceReferenceArgs(
                            id=network_interface.id,
                            primary=True,
                        )
                    ],
                ),
                os_profile=compute.OSProfileArgs(
                    admin_password=admin_password,
                    admin_username="dshadmin",
                    computer_name=vm_name,
                    custom_data=Output.secret(b64cloudinit),
                    linux_configuration=compute.LinuxConfigurationArgs(
                        patch_settings=compute.LinuxPatchSettingsArgs(
                            assessment_mode="ImageDefault",
                        ),
                        provision_vm_agent=True,
                    ),
                ),
                resource_group_name=props.resource_group_name,
                storage_profile=compute.StorageProfileArgs(
                    image_reference=compute.ImageReferenceArgs(
                        offer="0001-com-ubuntu-server-focal",
                        publisher="Canonical",
                        sku="20_04-LTS",
                        version="latest",
                    ),
                    os_disk=compute.OSDiskArgs(
                        caching="ReadWrite",
                        create_option="FromImage",
                        delete_option="Delete",
                        managed_disk=compute.ManagedDiskParametersArgs(
                            storage_account_type="Premium_LRS",
                        ),
                        name=f"{vm_name}-osdisk",
                    ),
                ),
                vm_name=vm_name,
                opts=ResourceOptions(
                    delete_before_replace=True, replace_on_changes=["os_profile"]
                ),
            )
