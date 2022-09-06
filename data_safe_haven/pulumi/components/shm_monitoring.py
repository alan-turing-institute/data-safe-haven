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

        # Register outputs
        self.automation_account = automation_account
        self.resource_group_name = Output.from_input(props.resource_group_name)
