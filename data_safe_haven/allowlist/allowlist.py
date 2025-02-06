from __future__ import annotations

from difflib import unified_diff
from typing import Self

from data_safe_haven.config import Context
from data_safe_haven.exceptions import DataSafeHavenAzureStorageError
from data_safe_haven.external import AzureSdk
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.types import AllowlistRepository


class Allowlist:
    """Allowlist for packages."""

    def __init__(
        self,
        repository: AllowlistRepository,
        sre_stack: SREProjectManager,
        allowlist: str | None = None,
    ):
        self.repository = repository
        self.sre_resource_group = sre_stack.output("sre_resource_group")
        self.storage_account_name = sre_stack.output("data")[
            "storage_account_data_configuration_name"
        ]
        self.share_name = sre_stack.output("allowlist_share_name")
        self.filename = sre_stack.output("allowlist_share_filenames")[repository.value]
        self.allowlist = str(allowlist) if allowlist else ""

    @classmethod
    def from_remote(
        cls: type[Self],
        *,
        context: Context,
        repository: AllowlistRepository,
        sre_stack: SREProjectManager,
    ) -> Self:
        azure_sdk = AzureSdk(subscription_name=context.subscription_name)
        allowlist = cls(repository=repository, sre_stack=sre_stack)
        try:
            share_file = azure_sdk.download_share_file(
                allowlist.filename,
                allowlist.sre_resource_group,
                allowlist.storage_account_name,
                allowlist.share_name,
            )
            allowlist.allowlist = share_file
            return allowlist
        except DataSafeHavenAzureStorageError as exc:
            msg = f"Storage account '{cls.storage_account_name}' does not exist."
            raise DataSafeHavenAzureStorageError(msg) from exc

    @classmethod
    def remote_exists(
        cls: type[Self],
        context: Context,
        *,
        repository: AllowlistRepository,
        sre_stack: SREProjectManager,
    ) -> bool:
        # Get the Azure SDK
        azure_sdk = AzureSdk(subscription_name=context.subscription_name)

        allowlist = cls(repository=repository, sre_stack=sre_stack)

        # Get the file share name
        share_list_exists = azure_sdk.file_share_exists(
            allowlist.filename,
            allowlist.sre_resource_group,
            allowlist.storage_account_name,
            allowlist.share_name,
        )
        return share_list_exists

    def upload(
        self,
        context: Context,
    ) -> None:
        # Get the Azure SDK
        azure_sdk = AzureSdk(subscription_name=context.subscription_name)

        azure_sdk.upload_file_share(
            self.allowlist,
            self.filename,
            self.sre_resource_group,
            self.storage_account_name,
            self.share_name,
        )

    def diff(self, other: Allowlist) -> list[str]:
        diff = list(
            unified_diff(
                self.allowlist.splitlines(),
                other.allowlist.splitlines(),
                fromfile="remote",
                tofile="local",
            )
        )
        return diff
