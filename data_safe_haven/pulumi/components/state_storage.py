# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import storage

# Local imports
from data_safe_haven.helpers import alphanumeric


class StateStorageProps:
    """Properties for StateStorageComponent"""

    def __init__(
        self,
        resource_group_name: Input[str],
        storage_name: Input[str],
    ):
        self.resource_group_name = resource_group_name
        self.storage_name = storage_name


class StateStorageComponent(ComponentResource):
    """Deploy container state storage with Pulumi"""

    def __init__(
        self, name: str, props: StateStorageProps, opts: ResourceOptions = None
    ):
        super().__init__("dsh:state_storage:StateStorageComponent", name, {}, opts)

        # Deploy storage account
        storage_account = storage.StorageAccount(
            "storage_account_state",
            account_name=props.storage_name[:24], # maximum of 24 characters
            kind="StorageV2",
            resource_group_name=props.resource_group_name,
            sku=storage.SkuArgs(name="Standard_LRS"),
        )

        # Retrieve storage account keys
        storage_account_keys = storage.list_storage_account_keys(
            account_name=storage_account.name,
            resource_group_name=props.resource_group_name,
        )

        # Register outputs
        self.access_key = Output.secret(storage_account_keys.keys[0].value)
        self.account_name = Output.from_input(storage_account.name)
        self.resource_group_name = Output.from_input(props.resource_group_name)
