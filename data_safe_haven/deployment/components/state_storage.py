# Third party imports
from pulumi import ComponentResource, Input, ResourceOptions
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
        super().__init__("dsh:StateStorage", name, {}, opts)

        self.resource_group_name = props.resource_group_name

        self.storage_account = storage.StorageAccount(
            "storage_account_state",
            account_name=f"stv{self._name}state",
            kind="StorageV2",
            resource_group_name=self.resource_group_name,
            sku=storage.SkuArgs(name="Standard_LRS"),
        )
        self.account_name = self.storage_account.name

        storage_account_keys = storage.list_storage_account_keys(
            account_name=self.account_name,
            resource_group_name=self.resource_group_name,
        )

        self.access_key = storage_account_keys.keys[0].value
