"""Load global and local settings from dotfiles"""

# For postponed evaluation of annotations https://peps.python.org/pep-0563
from __future__ import (
    annotations,
)

from pathlib import Path
from typing import ClassVar

import yaml
from azure.keyvault.keys import KeyVaultKey
from pydantic import BaseModel

from data_safe_haven import __version__
from data_safe_haven.external import AzureApi
from data_safe_haven.functions import alphanumeric
from data_safe_haven.types import (
    AzureLocation,
    AzureLongName,
    Guid,
)
from data_safe_haven.utility import config_dir


class Context(BaseModel, validate_assignment=True):
    admin_group_id: Guid
    location: AzureLocation
    name: str
    subscription_name: AzureLongName
    storage_container_name: ClassVar[str] = "config"
    pulumi_storage_container_name: ClassVar[str] = "pulumi"
    pulumi_encryption_key_name: ClassVar[str] = "pulumi-encryption-key"

    _pulumi_encryption_key = None

    @property
    def tags(self) -> dict[str, str]:
        return {
            "deployment": self.name,
            "deployed by": "Python",
            "project": "Data Safe Haven",
            "version": __version__,
        }

    @property
    def shm_name(self) -> str:
        return alphanumeric(self.name).lower()

    @property
    def work_directory(self) -> Path:
        return config_dir() / self.shm_name

    @property
    def resource_group_name(self) -> str:
        return f"shm-{self.shm_name}-rg-context"

    @property
    def storage_account_name(self) -> str:
        # maximum of 24 characters allowed
        return f"shm{self.shm_name[:14]}context"

    @property
    def key_vault_name(self) -> str:
        return f"shm-{self.shm_name[:9]}-kv-context"

    @property
    def managed_identity_name(self) -> str:
        return f"shm-{self.shm_name}-identity-reader-context"

    @property
    def pulumi_backend_url(self) -> str:
        return f"azblob://{self.pulumi_storage_container_name}"

    @property
    def pulumi_encryption_key(self) -> KeyVaultKey:
        if not self._pulumi_encryption_key:
            azure_api = AzureApi(subscription_name=self.subscription_name)
            self._pulumi_encryption_key = azure_api.get_keyvault_key(
                key_name=self.pulumi_encryption_key_name,
                key_vault_name=self.key_vault_name,
            )
        return self._pulumi_encryption_key

    @property
    def pulumi_encryption_key_version(self) -> str:
        """ID for the Pulumi encryption key"""
        key_id: str = self.pulumi_encryption_key.id
        return key_id.split("/")[-1]

    @property
    def pulumi_secrets_provider_url(self) -> str:
        return f"azurekeyvault://{self.key_vault_name}.vault.azure.net/keys/{self.pulumi_encryption_key_name}/{self.pulumi_encryption_key_version}"

    def to_yaml(self) -> str:
        return yaml.dump(self.model_dump(), indent=2)
