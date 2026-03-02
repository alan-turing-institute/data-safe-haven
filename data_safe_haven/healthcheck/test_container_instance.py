import pytest

from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.types import AzureSubscriptionName

from .healthcheck_utils import BaseContainerInstanceTest


class TestContainerInstance(BaseContainerInstanceTest):

    @pytest.mark.parametrize("output_key", ["apt_proxy_server", "sre_clamav_mirror", "remote_desktop"])
    def test_container_state(
        self,
        output_key: str,
        project_manager: SREProjectManager,
        subscription_name: AzureSubscriptionName,
    ) -> None:
        self.check_container_state(
            output_key, project_manager, subscription_name
        )
