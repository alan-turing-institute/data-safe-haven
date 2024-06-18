"""SHM configuration file backed by blob storage"""

from __future__ import annotations

from typing import ClassVar, Self

from data_safe_haven.serialisers import AzureSerialisableModel

from .config_sections import ConfigSectionAzure, ConfigSectionSHM


class SHMConfig(AzureSerialisableModel):
    config_type: ClassVar[str] = "SHMConfig"
    filename: ClassVar[str] = "shm.yaml"
    azure: ConfigSectionAzure
    shm: ConfigSectionSHM

    def is_complete(self) -> bool:
        if not all((self.azure, self.shm)):
            return False
        return True

    @classmethod
    def template(cls: type[Self]) -> SHMConfig:
        """Create SHMConfig without validation to allow "replace me" prompts."""
        return SHMConfig.model_construct(
            azure=ConfigSectionAzure.model_construct(
                subscription_id="ID of the Azure subscription that the TRE will be deployed to",
                tenant_id="Home tenant for the Azure account used to deploy infrastructure: `az account show`",
            ),
            shm=ConfigSectionSHM.model_construct(
                entra_tenant_id="Tenant ID for the Entra ID used to manage TRE users",
                fqdn="Domain you want your users to belong to and where your TRE will be deployed",
            ),
        )
