from data_safe_haven.external import AzureContainerInstance
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.types import AzureSubscriptionName


class BaseContainerInstanceTest:

    def check_container_state(
        self,
        output_key: str,
        project_manager: SREProjectManager,
        subscription_name: AzureSubscriptionName,
    ) -> None:
        container_instance: AzureContainerInstance | None = (
            self._get_container_instance(output_key, project_manager, subscription_name)
        )
        assert (
            container_instance is not None
        ), f"Cannot get outputs with key {output_key}. Do you need to redeploy?"

        for container in container_instance.containers:
            if (
                container
                and container.instance_view
                and container.instance_view.current_state
            ):
                container_state: str = container.instance_view.current_state.state
                assert (
                    container_state == "Running"
                ), f"Container {container.name} from group {container_instance.container_group_name} has state {container_state}"

    def _get_container_instance(
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
