import pytest

from data_safe_haven.config import SREConfig
from data_safe_haven.external import AzureContainerInstance
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.types import AzureSubscriptionName, SoftwarePackageCategory

from .healthcheck_utils import BaseContainerInstanceTest


class TestContainerInstance(BaseContainerInstanceTest):

    def test_software_repositories_container(
        self,
        project_manager: SREProjectManager,
        subscription_name: AzureSubscriptionName,
        sre_config: SREConfig,
    ) -> None:

        output_key: str = "software_repositories"
        if (
            sre_config.sre.allow_workspace_internet
            or sre_config.sre.software_packages == SoftwarePackageCategory.NONE
        ):
            container_instance: AzureContainerInstance | None = (
                self.get_container_instance(
                    output_key, project_manager, subscription_name
                )
            )

            assert (  # noqa: S101
                container_instance is None
            ), f"A TRE with {sre_config.sre.allow_workspace_internet=} and {sre_config.sre.software_packages=} should not have a Nexus container."

        else:
            self.check_container_state(output_key, project_manager, subscription_name)

    @pytest.mark.parametrize(
        "output_key",
        [
            "apt_proxy_server",
            "sre_clamav_mirror",
            "sre_gitea_server",
            "remote_desktop",
            "sre_hedgedoc_server",
            "sre_identity",
        ],
    )
    def test_container_state(
        self,
        output_key: str,
        project_manager: SREProjectManager,
        subscription_name: AzureSubscriptionName,
    ) -> None:
        self.check_container_state(output_key, project_manager, subscription_name)
