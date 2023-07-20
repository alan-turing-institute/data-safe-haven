"""Register a VM as an Azure Automation DSC node"""
# Standard library imports
import pathlib
import time
from typing import Dict, Optional, Sequence

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import automation, compute

# Local imports
from data_safe_haven.utility import FileReader
from ..dynamic.compiled_dsc import CompiledDsc, CompiledDscProps


class AutomationDscNodeProps:
    """Props for the AutomationDscNode class"""

    def __init__(
        self,
        automation_account_name: Input[str],
        automation_account_registration_key: Input[str],
        automation_account_registration_url: Input[str],
        automation_account_resource_group_name: Input[str],
        configuration_name: Input[str],
        dsc_description: Input[str],
        dsc_file: Input[FileReader],
        dsc_parameters: Input[Dict[str, str]],
        dsc_required_modules: Input[Sequence[str]],
        location: Input[str],
        subscription_name: Input[str],
        vm_name: Input[str],
        vm_resource_group_name: Input[str],
    ):
        self.automation_account_name = automation_account_name
        self.automation_account_registration_key = automation_account_registration_key
        self.automation_account_registration_url = automation_account_registration_url
        self.automation_account_resource_group_name = (
            automation_account_resource_group_name
        )
        self.configuration_name = configuration_name
        self.dsc_description = dsc_description
        self.dsc_file = dsc_file
        self.dsc_parameters = dsc_parameters
        self.dsc_required_modules = dsc_required_modules
        self.location = location
        self.subscription_name = subscription_name
        self.vm_name = vm_name
        self.vm_resource_group_name = vm_resource_group_name


class AutomationDscNode(ComponentResource):
    """Deploy an AutomationDscNode with Pulumi"""

    def __init__(
        self,
        name: str,
        props: AutomationDscNodeProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:common:AutomationDscNode", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)
        resources_path = pathlib.Path(__file__).parent.parent.parent / "resources"

        # Upload the primary domain controller DSC
        dsc = automation.DscConfiguration(
            f"{self._name}_dsc",
            automation_account_name=props.automation_account_name,
            configuration_name=props.configuration_name,
            description=props.dsc_description,
            location=props.location,
            name=props.configuration_name,
            resource_group_name=props.automation_account_resource_group_name,
            source=automation.ContentSourceArgs(
                hash=automation.ContentHashArgs(
                    algorithm="sha256",
                    value=Output.from_input(props.dsc_file).apply(lambda f: f.sha256()),
                ),
                type="embeddedContent",
                value=Output.from_input(props.dsc_file).apply(
                    lambda f: f.file_contents()
                ),
            ),
            opts=ResourceOptions.merge(
                ResourceOptions(
                    delete_before_replace=True, replace_on_changes=["source.hash"]
                ),
                child_opts,
            ),
        )
        dsc_compiled = CompiledDsc(
            f"{self._name}_dsc_compiled",
            CompiledDscProps(
                automation_account_name=props.automation_account_name,
                configuration_name=dsc.name,
                content_hash=Output.from_input(props.dsc_file).apply(
                    lambda f: f.sha256()
                ),
                location=props.location,
                parameters=props.dsc_parameters,
                resource_group_name=props.automation_account_resource_group_name,
                required_modules=props.dsc_required_modules,
                subscription_name=props.subscription_name,
            ),
            opts=ResourceOptions.merge(ResourceOptions(depends_on=[dsc]), child_opts),
        )
        dsc_extension = compute.VirtualMachineExtension(
            f"{self._name}_dsc_extension",
            auto_upgrade_minor_version=True,
            location=props.location,
            publisher="Microsoft.Powershell",
            resource_group_name=props.vm_resource_group_name,
            settings={
                "configurationArguments": {
                    "RegistrationUrl": props.automation_account_registration_url,
                    "ConfigurationMode": "ApplyAndMonitor",
                    "RebootNodeIfNeeded": True,
                    "ActionAfterReboot": "ContinueConfiguration",
                    "ConfigurationModeFrequencyMins": 15,
                    "RefreshFrequencyMins": 30,
                    "AllowModuleOverwrite": False,
                    "NodeConfigurationName": f"{props.configuration_name}.localhost",
                }
            },
            protected_settings={
                "configurationArguments": {
                    "registrationKey": {
                        "userName": f"notused{time.time()}",  # force refresh every time
                        "Password": props.automation_account_registration_key,
                    }
                }
            },
            type="DSC",
            type_handler_version="2.77",
            vm_name=props.vm_name,
            vm_extension_name="Microsoft.Powershell.DSC",
            opts=ResourceOptions.merge(
                ResourceOptions(depends_on=[dsc_compiled]),
                child_opts,
            ),
        )
