from data_safe_haven.external import AzureContainerInstance


class BaseContainerInstanceTest:

    def check_container_state(self, container_instance: AzureContainerInstance) -> None:
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
