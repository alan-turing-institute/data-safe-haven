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
                subscription_id="Azure subscription ID",
                tenant_id="Azure tenant ID",
            ),
            shm=ConfigSectionSHM.model_construct(
                entra_tenant_id="Entra tenant ID",
                fqdn="TRE domain name",
            ),
        )
