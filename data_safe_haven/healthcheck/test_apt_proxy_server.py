from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.types import AzureSubscriptionName

from .healthcheck_utils import BaseContainerInstanceTest


class TestAptProxyContainerInstance(BaseContainerInstanceTest):

    def test_container_state(
        self,
        project_manager: SREProjectManager,
        subscription_name: AzureSubscriptionName,
    ) -> None:
        self.check_container_state(
            "apt_proxy_server", project_manager, subscription_name
        )
