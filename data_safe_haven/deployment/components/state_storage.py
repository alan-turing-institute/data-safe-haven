# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import storage


class StateStorageProps:
    """Properties for StateStorageComponent"""

    def __init__(
        self,
        resource_group_name: Input[str],
    ):
        self.resource_group_name = resource_group_name


class StateStorageComponent(ComponentResource):
    """Deploy container state storage with Pulumi"""

    def __init__(
        self, name: str, props: StateStorageProps, opts: ResourceOptions = None
    ):
        super().__init__("dsh:state_storage:StateStorageComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        storage_account = storage.StorageAccount(
            "storage_account_state",
            account_name=f"st{self._name}state",
            kind="StorageV2",
            resource_group_name=props.resource_group_name,
            sku=storage.SkuArgs(name="Standard_LRS"),
            opts=child_opts,
        )

        storage_account_keys = storage.list_storage_account_keys(
            account_name=storage_account.name,
            resource_group_name=props.resource_group_name,
            opts=child_opts,
        )

        # Register outputs
        self.access_key = Output.secret(storage_account_keys.keys[0].value)
        self.account_name = Output.from_input(storage_account.name)
        self.resource_group_name = Output.from_input(props.resource_group_name)