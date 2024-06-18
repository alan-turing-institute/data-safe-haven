"""SRE configuration file backed by blob storage"""

from __future__ import annotations

from typing import ClassVar, Self

from data_safe_haven.functions import sanitise_sre_name
from data_safe_haven.serialisers import AzureSerialisableModel, ContextBase

from .config_sections import (
    ConfigSectionAzure,
    ConfigSectionSRE,
    ConfigSubsectionRemoteDesktopOpts,
)


class SREConfig(AzureSerialisableModel):
    config_type: ClassVar[str] = "SREConfig"
    default_filename: ClassVar[str] = "sre.yaml"
    azure: ConfigSectionAzure
    sre: ConfigSectionSRE

    def is_complete(self) -> bool:
        if not all((self.azure, self.sre)):
            return False
        return True

    @classmethod
    def filename(cls: type[Self], sre_name: str) -> str:
        """Construct a canonical filename."""
        return f"sre-{sanitise_sre_name(sre_name)}.yaml"

    @classmethod
    def from_remote_by_name(
        cls: type[Self], context: ContextBase, sre_name: str
    ) -> SREConfig:
        """Load an SREConfig from Azure storage."""
        return cls.from_remote(context, filename=cls.filename(sre_name))

    @classmethod
    def template(cls: type[Self]) -> SREConfig:
        """Create SREConfig without validation to allow "replace me" prompts."""
        return SREConfig.model_construct(
            azure=ConfigSectionAzure.model_construct(
                subscription_id="ID of the Azure subscription that the SRE will be deployed to",
                tenant_id="Home tenant for the Azure account used to deploy infrastructure: `az account show`",
            ),
            sre=ConfigSectionSRE.model_construct(
                admin_email_address="Email address shared by all administrators",
                admin_ip_addresses=["List of IP addresses belonging to administrators"],
                databases=["List of database systems to deploy"],
                data_provider_ip_addresses=[
                    "List of IP addresses belonging to data providers"
                ],
                remote_desktop=ConfigSubsectionRemoteDesktopOpts.model_construct(
                    allow_copy="True/False: whether to allow copying text out of the environment",
                    allow_paste="True/False: whether to allow pasting text into the environment",
                ),
                research_user_ip_addresses=["List of IP addresses belonging to users"],
                software_packages="any/pre-approved/none: which packages from external repositories to allow",
                timezone="Timezone in pytz format (eg. Europe/London)",
                workspace_skus=[
                    "List of Azure VM SKUs - see cloudprice.net for list of valid SKUs"
                ],
            ),
        )
