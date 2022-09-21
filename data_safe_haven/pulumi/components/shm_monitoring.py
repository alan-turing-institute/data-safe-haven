# Third party imports
from pulumi import ComponentResource, Input, ResourceOptions, Output
from pulumi_azure_native import automation


class SHMMonitoringProps:
    """Properties for SHMMonitoringComponent"""

    def __init__(
        self,
        location: Input[str],
        resource_group_name: Input[str],
    ):
        self.location = location
        self.resource_group_name = resource_group_name


class SHMMonitoringComponent(ComponentResource):
    """Deploy SHM secrets with Pulumi"""

    def __init__(
        self, name: str, props: SHMMonitoringProps, opts: ResourceOptions = None
    ):
        super().__init__("dsh:shm_monitoring:SHMMonitoringComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        automation_account = automation.AutomationAccount(
            "automationAccount",
            automation_account_name=f"{self._name}-automation",
            location=props.location,
            name=f"{self._name}-automation",
            resource_group_name=props.resource_group_name,
            sku=automation.SkuArgs(name="Free"),
            opts=child_opts,
        )

        automation_keys = automation.list_key_by_automation_account(
            automation_account.name, resource_group_name=props.resource_group_name
        )

        # List of modules as 'name: (version, SHA256 hash)'
        # Note that we exclude ComputerManagementDsc which is already present (https://docs.microsoft.com/en-us/azure/automation/shared-resources/modules#default-modules)
        modules = {
            "ActiveDirectoryDsc": (
                "6.2.0",
                "60b7cc2c578248f23c5b871b093db268a1c1bd89f5ccafc45d9a65c3f0621dca",
            ),
            "DnsServerDsc": (
                "3.0.0",
                "439bfba11cac20de8fae98d44de118f9a45f6e76ce01e0562f82784d389532bc",
            ),
            "NetworkingDsc": (
                "9.0.0",
                "c49b7059256f768062cdcf7e133cf52a806c7eb95eb34bfdd65f7cbca92d6a82",
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
                f"module_{module_name}",
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
                resource_group_name=props.resource_group_name,
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
        self.automation_account_primary_key = Output.secret(
            automation_keys.keys[0].value
        )
        self.resource_group_name = Output.secret(props.resource_group_name)
