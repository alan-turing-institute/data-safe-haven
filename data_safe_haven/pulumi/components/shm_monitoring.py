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
            automation_account_name=f"shm-{self._name}-automation",
            location=props.location,
            name=f"shm-{self._name}-automation",
            resource_group_name=props.resource_group_name,
            sku=automation.SkuArgs(name="Free"),
            opts=child_opts,
        )

        automation_keys = automation.list_key_by_automation_account(
            automation_account.name, resource_group_name=props.resource_group_name
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
