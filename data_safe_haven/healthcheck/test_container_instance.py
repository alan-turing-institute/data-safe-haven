from attrs import define

from data_safe_haven.external import AzureContainerInstance
from data_safe_haven.types import SoftwarePackageCategory

from .healthcheck_plugin import SREHeathCheckPlugin
from .healthcheck_utils import BaseContainerInstanceTest


@define
class TestContainerInstance(BaseContainerInstanceTest):

    _healthcheck_plugin: SREHeathCheckPlugin

    def test_software_repositories_container(
        self,
    ) -> None:

        output_key: str = "software_repositories"
        if (
            self._healthcheck_plugin.sre_config.sre.allow_workspace_internet
            or self._healthcheck_plugin.sre_config.sre.software_packages
            == SoftwarePackageCategory.NONE
        ):
            container_instance: AzureContainerInstance | None = (
                self.get_container_instance(
                    output_key,
                    self._healthcheck_plugin.project_manager,
                    self._healthcheck_plugin.subscription_name,
                )
            )

            assert (  # noqa: S101
                container_instance is None
            ), f"A TRE with {self._healthcheck_plugin.sre_config.sre.allow_workspace_internet=} and {self._healthcheck_plugin.sre_config.sre.software_packages=} should not have a Nexus container."

        else:
            self.check_container_state(
                output_key,
                self._healthcheck_plugin.project_manager,
                self._healthcheck_plugin.subscription_name,
            )

    def test_container_state(
        self,
        output_keys: list[str],
    ) -> None:
        for output_key in output_keys:
            self.check_container_state(
                output_key,
                self._healthcheck_plugin.project_manager,
                self._healthcheck_plugin.subscription_name,
            )
