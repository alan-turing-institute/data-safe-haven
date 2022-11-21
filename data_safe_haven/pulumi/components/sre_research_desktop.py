# Standard library imports
import base64
import pathlib
from typing import Sequence, Tuple

# Third party imports
import chevron
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import compute, network, resources

# Local imports


class SREResearchDesktopProps:
    """Properties for SREResearchDesktopComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        ip_addresses: Input[Sequence[str]],
        ldap_root_dn: Input[str],
        ldap_search_password: Input[str],
        ldap_server_ip: Input[str],
        location: Input[str],
        subnet_name: Input[str],
        virtual_network_resource_group_name: Input[str],
        virtual_network: Input[network.VirtualNetwork],
        vm_skus: Input[Sequence[Tuple[str, str]]],
    ):
        self.admin_password = admin_password
        self.ip_addresses = ip_addresses
        self.ldap_root_dn = ldap_root_dn
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.location = location
        self.subnet_name = subnet_name
        self.virtual_network = virtual_network
        self.virtual_network_resource_group_name = virtual_network_resource_group_name
        self.vm_details = Output.all(vm_skus=vm_skus, ip_addresses=ip_addresses).apply(
            lambda args: [
                (*vm_sku, ip_address)
                for vm_sku, ip_address in zip(args["vm_skus"], args["ip_addresses"])
            ]
        )


class SREResearchDesktopComponent(ComponentResource):
    """Deploy secure research desktops with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SREResearchDesktopProps,
        opts: ResourceOptions = None,
    ):
        super().__init__("dsh:sre:SREResearchDesktopComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"rg-{stack_name}-research-desktops",
        )

        # Deploy a variable number of VMs depending on the input parameters
        Output.all(
            admin_password=props.admin_password,
            ldap_root_dn=props.ldap_root_dn,
            ldap_search_password=props.ldap_search_password,
            ldap_server_ip=props.ldap_server_ip,
            resource_group_name=resource_group.name,
            vm_details=props.vm_details,
        ).apply(
            lambda args: self.deploy(
                admin_password=args["admin_password"],
                ldap_root_dn=args["ldap_root_dn"],
                ldap_search_password=args["ldap_search_password"],
                ldap_server_ip=args["ldap_server_ip"],
                resource_group_name=args["resource_group_name"],
                sre_name=sre_name,
                vm_details=args["vm_details"],
                props=props,
                opts=child_opts,
            )
        )

        # Register outputs
        self.resource_group_name = resource_group.name

        # Register exports
        self.exports = props.vm_details

    def deploy(
        self,
        admin_password: str,
        ldap_root_dn: str,
        ldap_search_password: str,
        ldap_server_ip: str,
        resource_group_name: str,
        sre_name: str,
        vm_details: Sequence[Tuple[str, str]],
        props: SREResearchDesktopProps,
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
                "ldap_root_dn": ldap_root_dn,
                "ldap_search_password": ldap_search_password,
                "ldap_server_ip": ldap_server_ip,
            }
            cloudinit = chevron.render(f_cloudinit, mustache_values)
            b64cloudinit = base64.b64encode(cloudinit.encode("utf-8")).decode()

        # Deploy secure research desktops
        for vm_short_name, vm_size, ip_address in vm_details:
            vm_name = f"sre-{sre_name}-{vm_short_name}".replace("_", "-")
            vm_name_underscored = vm_name.replace("-", "_")

            # Define public IP address
            public_ip = network.PublicIPAddress(
                f"public_ip_{vm_name_underscored}",
                public_ip_address_name=f"{vm_name}-public-ip",
                public_ip_allocation_method="Static",
                resource_group_name=resource_group_name,
                sku=network.PublicIPAddressSkuArgs(name="Standard"),
                opts=opts,
            )
            network_interface = network.NetworkInterface(
                f"network_interface_{vm_name_underscored}",
                enable_accelerated_networking=True,
                ip_configurations=[
                    network.NetworkInterfaceIPConfigurationArgs(
                        name="ipconfigsreresearchdesktop",
                        public_ip_address=network.PublicIPAddressArgs(id=public_ip.id),
                        private_ip_address=ip_address,
                        subnet=network.SubnetArgs(id=snet_secure_research_desktop.id),
                    )
                ],
                network_interface_name=f"{vm_name_underscored}-nic",
                resource_group_name=resource_group_name,
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
                resource_group_name=resource_group_name,
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
