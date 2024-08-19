"""SRE configuration file backed by blob storage"""

from __future__ import annotations

from typing import ClassVar, Self

from data_safe_haven.functions import json_safe
from data_safe_haven.serialisers import AzureSerialisableModel, ContextBase
from data_safe_haven.types import SafeString

from .config_sections import (
    ConfigSectionAzure,
    ConfigSectionDockerHub,
    ConfigSectionSRE,
    ConfigSubsectionRemoteDesktopOpts,
    ConfigSubsectionStorageQuotaGB,
)


def sre_config_name(sre_name: str) -> str:
    """Construct a safe YAML filename given an input SRE name."""
    return f"sre-{json_safe(sre_name)}.yaml"


class SREConfig(AzureSerialisableModel):
    config_type: ClassVar[str] = "SREConfig"
    default_filename: ClassVar[str] = "sre.yaml"
    azure: ConfigSectionAzure
    description: str
    dockerhub: ConfigSectionDockerHub
    name: SafeString
    sre: ConfigSectionSRE

    @property
    def filename(self) -> str:
        """Construct a canonical filename for this SREConfig."""
        return sre_config_name(self.name)

    @classmethod
    def from_remote_by_name(
        cls: type[Self], context: ContextBase, sre_name: str
    ) -> SREConfig:
        """Load an SREConfig from Azure storage."""
        return cls.from_remote(context, filename=sre_config_name(sre_name))

    @classmethod
    def template(cls: type[Self]) -> SREConfig:
        """Create SREConfig without validation to allow "replace me" prompts."""
        return SREConfig.model_construct(
            azure=ConfigSectionAzure.model_construct(
                location="Azure location where SRE resources will be deployed.",
                subscription_id="ID of the Azure subscription that the SRE will be deployed to",
                tenant_id="Home tenant for the Azure account used to deploy infrastructure: `az account show`",
            ),
            dockerhub=ConfigSectionDockerHub.model_construct(
                access_token="A DockerHub personal access token (PAT) with 'Public Read-Only' permissions. See instructions here: https://docs.docker.com/security/for-developers/access-tokens/",
                username="Your DockerHub username.",
            ),
            description="Human-friendly name for this SRE deployment.",
            name="A name for this config which consists only of letters, numbers and underscores.",
            sre=ConfigSectionSRE.model_construct(
                admin_email_address="Email address shared by all administrators",
                admin_ip_addresses=["List of IP addresses belonging to administrators"],
                databases=["List of database systems to deploy"],  # type:ignore
                data_provider_ip_addresses=[
                    "List of IP addresses belonging to data providers"
                ],
                remote_desktop=ConfigSubsectionRemoteDesktopOpts.model_construct(
                    allow_copy="True/False: whether to allow copying text out of the environment.",  # type:ignore
                    allow_paste="True/False: whether to allow pasting text into the environment.",  # type:ignore
                ),
                research_user_ip_addresses=["List of IP addresses belonging to users"],
                software_packages="Which Python/R packages to allow users to install: [any/pre-approved/none]",  # type:ignore
                storage_quota_gb=ConfigSubsectionStorageQuotaGB.model_construct(
                    home="Total size in GiB across all home directories [minimum: 100].",  # type:ignore
                    shared="Total size in GiB for the shared directories [minimum: 100].",  # type:ignore
                ),
                timezone="Timezone in pytz format (eg. Europe/London)",
                workspace_skus=[
                    "List of Azure VM SKUs that will be used for data analysis."
                ],
            ),
        )
