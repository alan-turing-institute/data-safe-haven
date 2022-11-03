"""Pulumi component for SHM domain controllers"""
# Standard library import
import pathlib
from typing import Sequence

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import resources

# Local
from data_safe_haven.helpers import AzureIPv4Range, FileReader
from .automation_dsc_node import AutomationDscNode, AutomationDscNodeProps
from .virtual_machine import VMComponent, WindowsVMProps


class SHMDomainControllersProps:
    """Properties for SHMDomainControllersComponent"""

    def __init__(
        self,
        automation_account_modules: Input[Sequence[str]],
        automation_account_name: Input[str],
        automation_account_registration_key: Input[str],
        automation_account_registration_url: Input[str],
        automation_account_resource_group_name: Input[str],
        domain_fqdn: Input[str],
        domain_netbios_name: Input[str],
        location: Input[str],
        password_domain_computer_manager: Input[str],
        password_domain_admin: Input[str],
        password_domain_azuread_connect: Input[str],
        subnet_ip_range: Input[AzureIPv4Range],
        subnet_name: Input[str],
        subscription_name: Input[str],
        virtual_network_name: Input[str],
        virtual_network_resource_group_name: Input[str],
    ):
        self.automation_account_modules = automation_account_modules
        self.automation_account_name = automation_account_name
        self.automation_account_registration_url = automation_account_registration_url
        self.automation_account_registration_key = automation_account_registration_key
        self.automation_account_resource_group_name = (
            automation_account_resource_group_name
        )
        self.domain_fqdn = domain_fqdn
        self.domain_netbios_name = domain_netbios_name[:15]  # maximum of 15 characters
        self.location = location
        self.password_domain_admin = password_domain_admin
        self.password_domain_azuread_connect = password_domain_azuread_connect
        self.password_domain_computer_manager = password_domain_computer_manager
        # Note that usernames have a maximum of 20 characters
        self.username_domain_computer_manager = "dshcomputermanager"
        self.username_domain_azuread_connect = "dshazureadsync"
        self.username_domain_admin = "dshdomainadmin"
        self.subnet_ip_range = subnet_ip_range
        self.subnet_name = subnet_name
        self.subscription_name = subscription_name
        self.virtual_network_name = virtual_network_name
        self.virtual_network_resource_group_name = virtual_network_resource_group_name


class SHMDomainControllersComponent(ComponentResource):
    """Deploy SHM secrets with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        shm_name: str,
        props: SHMDomainControllersProps,
        opts: ResourceOptions = None,
    ):
        super().__init__("dsh:shm:SHMDomainControllersComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)
        resources_path = pathlib.Path(__file__).parent.parent.parent / "resources"

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"rg-{stack_name}-users",
        )

        # Create the DC
        # We use the domain admin credentials here as the VM admin is promoted to domain admin when setting up the domain
        primary_domain_controller = VMComponent(
            f"{self._name}_primary_domain_controller",
            WindowsVMProps(
                admin_password=props.password_domain_admin,
                admin_username=props.username_domain_admin,
                ip_address_public=True,
                ip_address_private=str(props.subnet_ip_range.available()[0]),
                location=props.location,
                resource_group_name=resource_group.name,
                subnet_name=props.subnet_name,
                virtual_network_name=props.virtual_network_name,
                virtual_network_resource_group_name=props.virtual_network_resource_group_name,
                vm_name=f"{stack_name[:11]}-dc1",
                vm_size="Standard_DS2_v2",
            ),
            opts=child_opts,
        )
        # Register the primary domain controller for automated DSC
        dsc_configuration_name = "PrimaryDomainController"
        dsc_reader = FileReader(
            resources_path
            / "desired_state_configuration"
            / f"{dsc_configuration_name}.ps1"
        )
        primary_domain_controller_dsc_node = AutomationDscNode(
            f"{self._name}_primary_domain_controller_dsc_node",
            AutomationDscNodeProps(
                automation_account_name=props.automation_account_name,
                automation_account_registration_key=props.automation_account_registration_key,
                automation_account_registration_url=props.automation_account_registration_url,
                automation_account_resource_group_name=props.automation_account_resource_group_name,
                configuration_name=dsc_configuration_name,
                dsc_file=dsc_reader,
                dsc_parameters={
                    "AzureADConnectPassword": props.password_domain_azuread_connect,
                    "AzureADConnectUsername": props.username_domain_azuread_connect,
                    "DomainAdministratorPassword": props.password_domain_admin,
                    "DomainAdministratorUsername": props.username_domain_admin,
                    "DomainComputerManagerPassword": props.password_domain_computer_manager,
                    "DomainComputerManagerUsername": props.username_domain_computer_manager,
                    "DomainName": props.domain_fqdn,
                    "DomainNetBios": props.domain_netbios_name,
                },
                dsc_required_modules=props.automation_account_modules,
                location=props.location,
                subscription_name=props.subscription_name,
                vm_name=primary_domain_controller.vm_name,
                vm_resource_group_name=resource_group.name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(depends_on=[primary_domain_controller])
            ),
        )

        # Register outputs
        self.resource_group_name = Output.from_input(resource_group.name)

        # Register exports
        self.exports = {
            "resource_group_name": Output.from_input(resource_group.name),
            "vm_name": primary_domain_controller.vm_name,
        }
