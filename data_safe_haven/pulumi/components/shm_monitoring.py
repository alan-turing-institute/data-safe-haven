"""Pulumi component for SHM monitoring"""
# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import automation, resources


class SHMMonitoringProps:
    """Properties for SHMMonitoringComponent"""

    def __init__(
        self,
        location: Input[str],
    ):
        self.location = location


class SHMMonitoringComponent(ComponentResource):
    """Deploy SHM secrets with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        shm_name: str,
        props: SHMMonitoringProps,
        opts: ResourceOptions = None,
    ):
        super().__init__("dsh:shm:SHMMonitoringComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"rg-{stack_name}-monitoring",
        )

        # Deploy automation account
        automation_account = automation.AutomationAccount(
            f"{self._name}_automationAccount",
            automation_account_name=f"{stack_name}-automation",
            location=props.location,
            name=f"{stack_name}-automation",
            resource_group_name=resource_group.name,
            sku=automation.SkuArgs(name="Free"),
            opts=child_opts,
        )

        automation_keys = automation.list_key_by_automation_account(
            automation_account.name, resource_group_name=resource_group.name
        )

        # List of modules as 'name: (version, SHA256 hash)'
        # Note that we exclude ComputerManagementDsc which is already present (https://docs.microsoft.com/en-us/azure/automation/shared-resources/modules#default-modules)
        modules = {
            "ActiveDirectoryDsc": (
                "6.2.0",
                "60b7cc2c578248f23c5b871b093db268a1c1bd89f5ccafc45d9a65c3f0621dca",
            ),
            "PSModulesDsc": (
                "1.0.13.0",
                "b970d3ef7f3694e49993ec434fd166befe493ccaf418b9a79281dda2e230603b",
            ),
            "xPendingReboot": (
                "0.4.0.0",
                "2fbada64b9b1424ee72badf3c332e9670c97e0cc4d20ce4aeb8a499bda2b4d4e",
            ),
        }
        for module_name, (module_version, sha256_hash) in modules.items():
            module = automation.Module(
                f"{self._name}_module_{module_name}",
                automation_account_name=automation_account.name,
                content_link=automation.ContentLinkArgs(
                    content_hash=automation.ContentHashArgs(
                        algorithm="sha256",
                        value=sha256_hash,
                    ),
                    uri=f"https://www.powershellgallery.com/api/v2/package/{module_name}/{module_version}",
                    version=module_version,
                ),
                module_name=module_name,
                resource_group_name=resource_group.name,
            )

        # Register outputs
        self.automation_account = automation_account
        self.automation_account_jrds_url = (
            automation_account.automation_hybrid_service_url
        )
        self.automation_account_agentsvc_url = Output.all(
            automation_account.automation_hybrid_service_url
        ).apply(
            lambda args: args[0]
            .replace("jrds", "agentsvc")
            .replace("/automationAccounts/", "/accounts/")
        )
        self.automation_account_modules = list(modules.keys())
        self.automation_account_primary_key = Output.secret(
            automation_keys.keys[0].value
        )
        self.resource_group_name = Output.secret(resource_group.name)
