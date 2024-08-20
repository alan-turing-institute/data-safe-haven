"""SHM configuration file backed by blob storage"""

from __future__ import annotations

from typing import ClassVar, Self

from data_safe_haven.external import AzureSdk
from data_safe_haven.serialisers import AzureSerialisableModel, ContextBase

from .config_sections import ConfigSectionAzure, ConfigSectionSHM


class SHMConfig(AzureSerialisableModel):
    config_type: ClassVar[str] = "SHMConfig"
    default_filename: ClassVar[str] = "shm.yaml"
    azure: ConfigSectionAzure
    shm: ConfigSectionSHM

    @classmethod
    def from_args(
        cls: type[Self],
        context: ContextBase,
        *,
        entra_tenant_id: str,
        fqdn: str,
        location: str,
    ) -> SHMConfig:
        """Construct an SHMConfig from arguments."""
        azure_sdk = AzureSdk(subscription_name=context.subscription_name)
        admin_group_id = (
            azure_sdk.entra_directory.get_id_from_groupname(context.admin_group_name)
            or "admin-group-id-not-found"
        )
        return SHMConfig.model_construct(
            azure=ConfigSectionAzure.model_construct(
                location=location,
                subscription_id=azure_sdk.subscription_id,
                tenant_id=azure_sdk.tenant_id,
            ),
            shm=ConfigSectionSHM.model_construct(
                admin_group_id=admin_group_id,
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
                admin_group_id="ID of a security group that contains all Azure infrastructure admins.",
                entra_tenant_id="Tenant ID for the Entra ID used to manage TRE users",
                fqdn="Domain you want your users to belong to and where your TRE will be deployed",
            ),
        )
