from data_safe_haven.external import AzureContainerInstance


class TestRemoteDesktopContainerInstance:

    def test_container_state(
        self,
        remote_desktop_container_instance: AzureContainerInstance,
    ) -> None:
        for container in remote_desktop_container_instance.containers:
            if (
                container
                and container.instance_view
                and container.instance_view.current_state
            ):
                container_state: str = container.instance_view.current_state.state
                assert (
                    container_state == "Runnings"
                ), f"Container {container.name} from group {remote_desktop_container_instance.container_group_name} has state {container_state}"
