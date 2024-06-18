"""Manage Pulumi accounts"""

from shutil import which
from typing import Any

from data_safe_haven.exceptions import DataSafeHavenPulumiError
from data_safe_haven.external import AzureApi, AzureCliSingleton


class PulumiAccount:
    """Manage and interact with Pulumi backend account"""

    def __init__(
        self,
        resource_group_name: str,
        storage_account_name: str,
        subscription_name: str,
    ):
        self.resource_group_name = resource_group_name
        self.storage_account_name = storage_account_name
        self.subscription_name = subscription_name
        self._env: dict[str, Any] | None = None

        # Ensure that Pulumi executable can be found
        if which("pulumi") is None:
            msg = "Unable to find Pulumi CLI executable in your path.\nPlease ensure that Pulumi is installed"
            raise DataSafeHavenPulumiError(msg)

        # Ensure Azure CLI account is correct
        # This will be needed to populate env
        AzureCliSingleton().confirm()

    @property
    def env(self) -> dict[str, Any]:
        """Get necessary Pulumi environment variables"""
        if not self._env:
            azure_api = AzureApi(self.subscription_name)
            storage_account_keys = azure_api.get_storage_account_keys(
                self.resource_group_name,
                self.storage_account_name,
            )
            self._env = {
                "AZURE_STORAGE_ACCOUNT": self.storage_account_name,
                "AZURE_STORAGE_KEY": str(storage_account_keys[0].value),
                "AZURE_KEYVAULT_AUTH_VIA_CLI": "true",
            }
        return self._env