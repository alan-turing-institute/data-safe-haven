# Standard library import
import json
import datetime
import pathlib

# Third party imports
from pulumi import ComponentResource, Input, ResourceOptions, Output

# Local
from .virtual_machine import VMComponent, WindowsVMProps
from .automation_dsc_node import AutomationDscNode, AutomationDscNodeProps
from data_safe_haven.helpers import AzureIPv4Range, FileReader


class SHMDomainControllersProps:
    """Properties for SHMDomainControllersComponent"""

    def __init__(
        self,
        admin_password: Input[str],
        automation_account_registration_key: Input[str],
        automation_account_registration_url: Input[str],
        automation_account_name: Input[str],
        automation_account_resource_group_name: Input[str],
        location: Input[str],
        resource_group_name: Input[str],
        subnet_ip_range: Input[AzureIPv4Range],
        subnet_name: Input[str],
        subscription_name: Input[str],
        virtual_network_name: Input[str],
        virtual_network_resource_group_name: Input[str],
    ):
        self.admin_password = admin_password
        self.automation_account_registration_url = automation_account_registration_url
        self.automation_account_registration_key = automation_account_registration_key
        self.automation_account_name = automation_account_name
        self.automation_account_resource_group_name = (
            automation_account_resource_group_name
        )
        self.location = location
        self.resource_group_name = resource_group_name
        self.subnet_ip_range = subnet_ip_range
        self.subnet_name = subnet_name
        self.subscription_name = subscription_name
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
        resources_path = pathlib.Path(__file__).parent.parent.parent / "resources"

        primary_domain_controller = VMComponent(
            "primary_domain_controller",
            WindowsVMProps(
                admin_password=props.admin_password,
                ip_address_private=str(props.subnet_ip_range.available()[0]),
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
        # Register the primary domain controller for automated DSC
        dsc_configuration_name = "PrimaryDomainController"
        dsc_reader = FileReader(
            resources_path
            / "desired_state_configuration"
            / f"{dsc_configuration_name}.ps1"
        )
        primary_domain_controller_dsc_node = AutomationDscNode(
            "primary_domain_controller_dsc_node",
            AutomationDscNodeProps(
                automation_account_name=props.automation_account_name,
                automation_account_registration_key=props.automation_account_registration_key,
                automation_account_registration_url=props.automation_account_registration_url,
                automation_account_resource_group_name=props.automation_account_resource_group_name,
                configuration_name=dsc_configuration_name,
                dsc_file=dsc_reader,
                location=props.location,
                subscription_name=props.subscription_name,
                vm_name=primary_domain_controller.vm_name,
                vm_resource_group_name=props.resource_group_name,
            ),
        )

        # Register outputs
        self.resource_group_name = Output.from_input(props.resource_group_name)
