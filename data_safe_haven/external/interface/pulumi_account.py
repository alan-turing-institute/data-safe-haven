"""Manage Pulumi accounts"""

import sys
from shutil import which
from typing import Any

from data_safe_haven.exceptions import DataSafeHavenPulumiError
from data_safe_haven.external import AzureSdk


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

    @property
    def env(self) -> dict[str, Any]:
        """Get necessary Pulumi environment variables"""
        if not self._env:
            azure_sdk = AzureSdk(self.subscription_name)
            storage_account_keys = azure_sdk.get_storage_account_keys(
                self.resource_group_name,
                self.storage_account_name,
            )
            self._env = {
                "AZURE_STORAGE_ACCOUNT": self.storage_account_name,
                "AZURE_STORAGE_KEY": str(storage_account_keys[0].value),
                "AZURE_KEYVAULT_AUTH_VIA_CLI": "true",
                "PULUMI_PYTHON_CMD": sys.executable,
            }
        return self._env
