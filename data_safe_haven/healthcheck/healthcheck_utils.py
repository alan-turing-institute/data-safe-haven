from typing import Protocol

from data_safe_haven.external import AzureContainerInstance
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.types import AzureSubscriptionName

from .healthcheck_plugin import SREHeathCheckPlugin


class HealthCheckError(Exception):
    pass


class HealthCheckTest(Protocol):

    def test(self, plugin: SREHeathCheckPlugin) -> str: ...


class BaseContainerInstanceTest:

    def check_container_state(
        self,
        output_key: str,
        project_manager: SREProjectManager,
        subscription_name: AzureSubscriptionName,
    ) -> list[str]:
        container_instance: AzureContainerInstance | None = self.get_container_instance(
            output_key, project_manager, subscription_name
        )
        assert (  # noqa: S101
            container_instance is not None
        ), f"Cannot get outputs with key {output_key}. Do you need to redeploy?"

        terminated_containers: list[str] = []
        for container in container_instance.containers:
            if (
                container
                and container.instance_view
                and container.instance_view.current_state
            ):
                container_state: str = container.instance_view.current_state.state
                if container_state != "Running":
                    terminated_containers.append(f"{container.name}")

        return terminated_containers

    def get_container_instance(
        self,
        output_key: str,
        project_manager: SREProjectManager,
        subscription_name: AzureSubscriptionName,
    ) -> AzureContainerInstance | None:
        try:
            output: dict[str, str] = project_manager.output(output_key)
            azure_container_instance = AzureContainerInstance(
                container_group_name=output["container_group_name"],
                resource_group_name=output["resource_group_name"],
                subscription_name=subscription_name,
            )

            return azure_container_instance
        except KeyError:
            return None
