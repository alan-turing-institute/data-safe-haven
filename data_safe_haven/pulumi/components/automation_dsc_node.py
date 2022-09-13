"""Register a VM as an Azure Automation DSC node"""
# Standard library imports
import datetime
import pathlib

# Third party imports
from pulumi import ComponentResource, Input, ResourceOptions
from pulumi_azure_native import automation, compute

# Local imports
from data_safe_haven.helpers import FileReader
from .compiled_dsc import CompiledDsc, CompiledDscProps


class AutomationDscNodeProps:
    """Props for the AutomationDscNode class"""

    def __init__(
        self,
        automation_account_name: Input[str],
        automation_account_registration_key: Input[str],
        automation_account_registration_url: Input[str],
        automation_account_resource_group_name: Input[str],
        configuration_name: Input[str],
        dsc_file: Input[FileReader],
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
        self.dsc_file = dsc_file
        self.location = location
        self.subscription_name = subscription_name
        self.vm_name = vm_name
        self.vm_resource_group_name = vm_resource_group_name


class AutomationDscNode(ComponentResource):
    """Deploy an AutomationDscNode with Pulumi"""

    def __init__(
        self, name: str, props: AutomationDscNodeProps, opts: ResourceOptions = None
    ):
        super().__init__("dsh:automation_dsc_node:AutomationDscNode", name, {}, opts)
        child_opts = ResourceOptions(parent=self)
        resources_path = pathlib.Path(__file__).parent.parent.parent / "resources"

        # Upload the primary domain controller DSC
        dsc = automation.DscConfiguration(
            f"{self._name}_dsc",
            automation_account_name=props.automation_account_name,
            configuration_name=props.configuration_name,
            description="DSC for Data Safe Haven primary domain controller",
            location=props.location,
            name=props.configuration_name,
            resource_group_name=props.automation_account_resource_group_name,
            source=automation.ContentSourceArgs(
                hash=automation.ContentHashArgs(
                    algorithm="sha256",
                    value=props.dsc_file.sha256(),
                ),
                type="embeddedContent",
                value=props.dsc_file.file_contents(),
            ),
        )
        dsc_compiled = CompiledDsc(
            f"{self._name}_dsc_compiled",
            CompiledDscProps(
                automation_account_name=props.automation_account_name,
                configuration_name=dsc.name,
                location=props.location,
                resource_group_name=props.automation_account_resource_group_name,
                subscription_name=props.subscription_name,
            ),
            opts=ResourceOptions.merge(child_opts, ResourceOptions(depends_on=[dsc])),
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
                    "Timestamp": datetime.datetime.utcnow().isoformat(
                        timespec="seconds"
                    ),
                }
            },
            protected_settings={
                "configurationArguments": {
                    "registrationKey": {
                        "userName": "notused",
                        "Password": props.automation_account_registration_key,
                    }
                }
            },
            type="DSC",
            type_handler_version="2.77",
            vm_name=props.vm_name,
            vm_extension_name="Microsoft.Powershell.DSC",
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(depends_on=[dsc_compiled])
            ),
        )
