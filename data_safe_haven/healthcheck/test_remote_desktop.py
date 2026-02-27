from data_safe_haven.external import AzureContainerInstance

from .healthcheck_utils import BaseContainerInstanceTest


class TestRemoteDesktopContainerInstance(BaseContainerInstanceTest):

    def test_container_state(
        self,
        remote_desktop_container_instance: AzureContainerInstance,
    ) -> None:
        self.check_container_state(remote_desktop_container_instance)
