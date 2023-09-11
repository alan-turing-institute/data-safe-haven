"""Register a VM as an Azure Automation DSC node"""
from collections.abc import Mapping, Sequence

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import automation, compute

from data_safe_haven.infrastructure.components.dynamic import (
    CompiledDsc,
    CompiledDscProps,
)
from data_safe_haven.infrastructure.components.wrapped import (
    WrappedAutomationAccount,
)
from data_safe_haven.utility import FileReader


class AutomationDscNodeProps:
    """Props for the AutomationDscNode class"""

    def __init__(
        self,
        automation_account: WrappedAutomationAccount,
        configuration_name: Input[str],
        dsc_description: Input[str],
        dsc_file: Input[FileReader],
        dsc_parameters: Input[dict[str, str]],
        dsc_required_modules: Input[Sequence[str]],
        location: Input[str],
        subscription_name: Input[str],
        vm_name: Input[str],
        vm_resource_group_name: Input[str],
    ) -> None:
        self.automation_account = automation_account
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
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:common:AutomationDscNode", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Upload the primary domain controller DSC
        dsc = automation.DscConfiguration(
            f"{self._name}_dsc",
            automation_account_name=props.automation_account.name,
            configuration_name=props.configuration_name,
            description=props.dsc_description,
            location=props.location,
            name=props.configuration_name,
            resource_group_name=props.automation_account.resource_group_name,
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
                child_opts,
                ResourceOptions(
                    delete_before_replace=True,
                    depends_on=[props.automation_account],
                    replace_on_changes=["source.hash"],
                ),
            ),
            tags=child_tags,
        )
        dsc_compiled = CompiledDsc(
            f"{self._name}_dsc_compiled",
            CompiledDscProps(
                automation_account_name=props.automation_account.name,
                configuration_name=dsc.name,
                location=props.location,
                parameters=props.dsc_parameters,
                resource_group_name=props.automation_account.resource_group_name,
                required_modules=props.dsc_required_modules,
                subscription_name=props.subscription_name,
            ),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    depends_on=[dsc],
                ),
            ),
        )
        compute.VirtualMachineExtension(
            f"{self._name}_dsc_extension",
            auto_upgrade_minor_version=True,
            location=props.location,
            publisher="Microsoft.Powershell",
            resource_group_name=props.vm_resource_group_name,
            settings={
                "configurationArguments": {
                    "ActionAfterReboot": "ContinueConfiguration",
                    "AllowModuleOverwrite": True,
                    "ConfigurationMode": "ApplyAndMonitor",
                    "ConfigurationModeFrequencyMins": 15,
                    "NodeConfigurationName": dsc_compiled.local_configuration_name,
                    "RebootNodeIfNeeded": True,
                    "RefreshFrequencyMins": 30,
                    "RegistrationUrl": props.automation_account.agentsvc_url,
                }
            },
            protected_settings={
                "configurationArguments": {
                    "registrationKey": {
                        "userName": "notused",
                        "Password": props.automation_account.primary_key,
                    }
                }
            },
            type="DSC",
            type_handler_version="2.77",
            vm_name=props.vm_name,
            vm_extension_name="Microsoft.Powershell.DSC",
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    depends_on=[dsc_compiled],
                ),
            ),
            tags=child_tags,
        )
