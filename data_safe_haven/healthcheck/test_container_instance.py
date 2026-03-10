from attrs import define

from data_safe_haven.external import AzureContainerInstance
from data_safe_haven.types import SoftwarePackageCategory

from .healthcheck_plugin import SREHeathCheckPlugin
from .healthcheck_utils import BaseContainerInstanceTest, HealthCheckError


class TestSoftwareRepositoriesContainer(BaseContainerInstanceTest):

    def test(self, healthcheck_plugin: SREHeathCheckPlugin) -> str:

        output_key: str = "software_repositories"
        allow_workspace_internet: bool = (
            healthcheck_plugin.sre_config.sre.allow_workspace_internet
        )
        software_packages: SoftwarePackageCategory = (
            healthcheck_plugin.sre_config.sre.software_packages
        )
        if (
            allow_workspace_internet
            or software_packages == SoftwarePackageCategory.NONE
        ):
            container_instance: AzureContainerInstance | None = (
                self.get_container_instance(
                    output_key,
                    healthcheck_plugin.project_manager,
                    healthcheck_plugin.subscription_name,
                )
            )

            assert (  # noqa: S101
                container_instance is None
            ), f"A TRE with {healthcheck_plugin.sre_config.sre.allow_workspace_internet=} and {healthcheck_plugin.sre_config.sre.software_packages=} should not have a Nexus container."
            return f"There's no {output_key} container in an SRE with {allow_workspace_internet=} and {software_packages=}"
        else:
            terminated_containers: list[str] = self.check_container_state(
                output_key,
                healthcheck_plugin.project_manager,
                healthcheck_plugin.subscription_name,
            )

            if terminated_containers:
                error_message: str = (
                    f"The following containers from {output_key} are not running: {terminated_containers=}"
                )
                raise HealthCheckError(error_message)
            return f"All containers from {output_key} are in 'Running' state"


@define
class TestContainerInstance(BaseContainerInstanceTest):
    output_key: str

    def test(self, healthcheck_plugin: SREHeathCheckPlugin) -> str:
        terminated_containers: list[str] = self.check_container_state(
            self.output_key,
            healthcheck_plugin.project_manager,
            healthcheck_plugin.subscription_name,
        )

        if terminated_containers:
            error_message: str = (
                f"The following containers from {self.output_key} are not running: {terminated_containers=}"
            )
            raise HealthCheckError(error_message)

        return f"All containers from {self.output_key} are in 'Running' state"
