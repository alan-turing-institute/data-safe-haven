"""SRE configuration file backed by blob storage"""

from __future__ import annotations

from typing import ClassVar, Self

from data_safe_haven.functions import sanitise_sre_name
from data_safe_haven.serialisers import AzureSerialisableModel, ContextBase
from data_safe_haven.types import (
    SoftwarePackageCategory,
)

from .config_sections import (
    ConfigSectionAzure,
    ConfigSectionSRE,
    ConfigSubsectionRemoteDesktopOpts,
)


class SREConfig(AzureSerialisableModel):
    config_type: ClassVar[str] = "SREConfig"
    filename: ClassVar[str] = "sre.yaml"
    azure: ConfigSectionAzure
    sre: ConfigSectionSRE

    def is_complete(self) -> bool:
        if not all((self.azure, self.sre)):
            return False
        return True

    @classmethod
    def sre_from_remote(
        cls: type[Self], context: ContextBase, sre_name: str
    ) -> SREConfig:
        """Load an SREConfig from Azure storage."""
        return cls.from_remote(context, filename=cls.sre_filename_from_name(sre_name))

    @classmethod
    def sre_filename_from_name(cls: type[Self], sre_name: str) -> str:
        """Construct a canonical filename."""
        return f"sre-{sanitise_sre_name(sre_name)}.yaml"

    @classmethod
    def template(cls: type[Self]) -> SREConfig:
        """Create SREConfig without validation to allow "replace me" prompts."""
        return SREConfig.model_construct(
            azure=ConfigSectionAzure.model_construct(
                subscription_id="Azure subscription ID",
                tenant_id="Azure tenant ID",
            ),
            sre=ConfigSectionSRE.model_construct(
                admin_email_address="Admin email address",
                databases=["List of database systems to enable"],
                data_provider_ip_addresses=["Data provider IP addresses"],
                remote_desktop=ConfigSubsectionRemoteDesktopOpts.model_construct(
                    allow_copy="Whether to allow copying text out of the environment",
                    allow_paste="Whether to allow pasting text into the environment",
                ),
                workspace_skus=[
                    "Azure VM SKUs - see cloudprice.net for list of valid SKUs"
                ],
                research_user_ip_addresses=["Research user IP addresses"],
                software_packages=SoftwarePackageCategory.ANY,
            ),
        )
