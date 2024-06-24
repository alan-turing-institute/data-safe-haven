"""SHM configuration file backed by blob storage"""

from __future__ import annotations

from typing import ClassVar, Self

from data_safe_haven.external import AzureApi
from data_safe_haven.serialisers import AzureSerialisableModel, ContextBase

from .config_sections import ConfigSectionAzure, ConfigSectionSHM


class SHMConfig(AzureSerialisableModel):
    config_type: ClassVar[str] = "SHMConfig"
    default_filename: ClassVar[str] = "shm.yaml"
    azure: ConfigSectionAzure
    shm: ConfigSectionSHM

    @classmethod
    def from_local(
        cls: type[Self],
        context: ContextBase,
        *,
        entra_tenant_id: str,
        fqdn: str,
        location: str,
    ) -> SHMConfig:
        """Construct an AzureSerialisableModel from a YAML file in Azure storage."""
        azure_api = AzureApi(subscription_name=context.subscription_name)
        return SHMConfig.model_construct(
            azure=ConfigSectionAzure.model_construct(
                location=location,
                subscription_id=azure_api.subscription_id,
                tenant_id=azure_api.tenant_id,
            ),
            shm=ConfigSectionSHM.model_construct(
                entra_tenant_id=entra_tenant_id,
                fqdn=fqdn,
            ),
        )

    @classmethod
    def template(cls: type[Self]) -> SHMConfig:
        """Create SHMConfig without validation to allow "replace me" prompts."""
        return SHMConfig.model_construct(
            azure=ConfigSectionAzure.model_construct(
                location="Azure location where SHM resources will be deployed.",
                subscription_id="ID of the Azure subscription that the SHM will be deployed to",
                tenant_id="Home tenant for the Azure account used to deploy infrastructure: `az account show`",
            ),
            shm=ConfigSectionSHM.model_construct(
                entra_tenant_id="Tenant ID for the Entra ID used to manage TRE users",
                fqdn="Domain you want your users to belong to and where your TRE will be deployed",
            ),
        )
