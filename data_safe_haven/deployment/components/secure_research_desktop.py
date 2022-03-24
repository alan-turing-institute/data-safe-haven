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
        ip_addresses: Input[Sequence[str]],
        ldap_group_base_dn: Input[str],
        ldap_root_dn: Input[str],
        ldap_search_password: Input[str],
        ldap_server_ip: Input[str],
        ldap_user_base_dn: Input[str],
        resource_group_name: Input[str],
        virtual_network_name: Input[str],
        virtual_network_resource_group: Input[str],
        vm_sizes: Sequence[Input[str]],
        subnet_name: Optional[Input[str]] = "SecureResearchDesktopSubnet",
    ):
        self.ip_addresses = ip_addresses
        self.ldap_group_base_dn = ldap_group_base_dn
        self.ldap_root_dn = ldap_root_dn
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.ldap_user_base_dn = ldap_user_base_dn
        self.resource_group_name = resource_group_name
        self.subnet_name = subnet_name
        self.virtual_network_name = virtual_network_name
        self.virtual_network_resource_group = virtual_network_resource_group
        self.vm_sizes = vm_sizes


class SecureResearchDesktopComponent(ComponentResource):
    """Deploy secure research desktops with Pulumi"""

    def __init__(
        self, name: str, props: SecureResearchDesktopProps, opts: ResourceOptions = None
    ):
        super().__init__("dsh:srd:SecureResearchDesktopComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Deploy a variable number of VMs depending on the input parameters
        Output.all(
            ip_addresses=props.ip_addresses,
            ldap_group_base_dn=props.ldap_group_base_dn,
            ldap_root_dn=props.ldap_root_dn,
            ldap_search_password=props.ldap_search_password,
            ldap_server_ip=props.ldap_server_ip,
            ldap_user_base_dn=props.ldap_user_base_dn,
            vm_sizes=props.vm_sizes,
        ).apply(
            lambda args: self.deploy(
                ip_addresses=args["ip_addresses"],
                ldap_group_base_dn=args["ldap_group_base_dn"],
                ldap_root_dn=args["ldap_root_dn"],
                ldap_search_password=args["ldap_search_password"],
                ldap_server_ip=args["ldap_server_ip"],
                ldap_user_base_dn=args["ldap_user_base_dn"],
                vm_sizes=args["vm_sizes"],
                props=props,
                opts=child_opts,
            )
        )

    def deploy(
        self,
        ip_addresses: Sequence[str],
        ldap_group_base_dn: str,
        ldap_root_dn: str,
        ldap_search_password: str,
        ldap_server_ip: str,
        ldap_user_base_dn: str,
        vm_sizes: Sequence[str],
        props: SecureResearchDesktopProps,
        opts: ResourceOptions = None,
    ):
        # Retrieve existing resources
        snet_secure_research_desktop = network.get_subnet(
            subnet_name=props.subnet_name,
            resource_group_name=props.virtual_network_resource_group,
            virtual_network_name=props.virtual_network_name,
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
        for idx, (vm_size, ip_address) in enumerate(
            zip(vm_sizes, ip_addresses), start=1
        ):
            category = "gpu" if vm_size.startswith("Standard_N") else "cpu"
            vm_name = f"vm-{self._name}-srd-{category}{idx:02d}"

            # Define public IP address
            public_ip = network.PublicIPAddress(
                f"public_ip_{vm_name}",
                public_ip_address_name=f"{vm_name}-public-ip",
                public_ip_allocation_method="Static",
                resource_group_name=props.resource_group_name,
                sku=network.PublicIPAddressSkuArgs(name="Standard"),
                opts=opts,
            )
            network_interface = network.NetworkInterface(
                f"network_interface_{vm_name}",
                enable_accelerated_networking=True,
                ip_configurations=[
                    network.NetworkInterfaceIPConfigurationArgs(
                        name="ipconfigsecureresearchdesktop",
                        public_ip_address=network.PublicIPAddressArgs(id=public_ip.id),
                        private_ip_address=ip_address,
                        subnet=network.SubnetArgs(id=snet_secure_research_desktop.id),
                    )
                ],
                network_interface_name=f"{vm_name}-nic",
                resource_group_name=props.resource_group_name,
                opts=opts,
            )
            virtual_machine = compute.VirtualMachine(
                f"virtual_machine_{vm_name}",
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
                    admin_password="P4ssw0rd",
                    admin_username="dshadmin",
                    computer_name=vm_name,
                    custom_data=b64cloudinit,
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

        # Register outputs
        self.resource_group_name = Output.from_input(props.resource_group_name)
