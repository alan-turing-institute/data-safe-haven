from data_safe_haven.config import Config
from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.external import AzureApi


class Context:
    """Azure resources to support Data Safe Haven context"""

    def __init__(self, config: Config) -> None:
        self.azure_api_: AzureApi | None = None
        self.config = config
        self.tags = {"component": "context"} | self.config.tags.model_dump()

    @property
    def azure_api(self) -> AzureApi:
        """Load AzureAPI on demand

        Returns:
            AzureApi: An initialised AzureApi object
        """
        if not self.azure_api_:
            self.azure_api_ = AzureApi(
                subscription_name=self.config.context.subscription_name,
            )
        return self.azure_api_

    def create(self) -> None:
        """Create all desired resources

        Raises:
            DataSafeHavenAzureError if any resources cannot be created
        """
        try:
            self.config.azure.subscription_id = self.azure_api.subscription_id
            self.config.azure.tenant_id = self.azure_api.tenant_id
            resource_group = self.azure_api.ensure_resource_group(
                location=self.config.azure.location,
                resource_group_name=self.config.context.resource_group_name,
                tags=self.tags,
            )
            if not resource_group.name:
                msg = f"Resource group '{self.config.context.resource_group_name}' was not created."
                raise DataSafeHavenAzureError(msg)
            identity = self.azure_api.ensure_managed_identity(
                identity_name=self.config.context.managed_identity_name,
                location=resource_group.location,
                resource_group_name=resource_group.name,
            )
            storage_account = self.azure_api.ensure_storage_account(
                location=resource_group.location,
                resource_group_name=resource_group.name,
                storage_account_name=self.config.context.storage_account_name,
                tags=self.tags,
            )
            if not storage_account.name:
                msg = f"Storage account '{self.config.context.storage_account_name}' was not created."
                raise DataSafeHavenAzureError(msg)
            _ = self.azure_api.ensure_storage_blob_container(
                container_name=self.config.context.storage_container_name,
                resource_group_name=resource_group.name,
                storage_account_name=storage_account.name,
            )
            _ = self.azure_api.ensure_storage_blob_container(
                container_name=self.config.pulumi.storage_container_name,
                resource_group_name=resource_group.name,
                storage_account_name=storage_account.name,
            )
            keyvault = self.azure_api.ensure_keyvault(
                admin_group_id=self.config.azure.admin_group_id,
                key_vault_name=self.config.context.key_vault_name,
                location=resource_group.location,
                managed_identity=identity,
                resource_group_name=resource_group.name,
                tags=self.tags,
            )
            if not keyvault.name:
                msg = (
                    f"Keyvault '{self.config.context.key_vault_name}' was not created."
                )
                raise DataSafeHavenAzureError(msg)
            self.azure_api.ensure_keyvault_key(
                key_name=self.config.pulumi.encryption_key_name,
                key_vault_name=keyvault.name,
            )
        except Exception as exc:
            msg = f"Failed to create context resources.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

    def teardown(self) -> None:
        """Destroy all created resources

        Raises:
            DataSafeHavenAzureError if any resources cannot be destroyed
        """
        try:
            self.azure_api.remove_resource_group(
                self.config.context.resource_group_name
            )
        except Exception as exc:
            msg = f"Failed to destroy context resources.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc