import pytest

from data_safe_haven.external import AzureContainerInstance
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.logging import get_logger
from data_safe_haven.types import AzureSubscriptionName

from .healthcheck_plugin import SREHeathCheckPlugin


class SREHealthCheckRunner:
    """Healthcheck manager for a deployed SRE"""

    def __init__(
        self,
        sre_project_manager: SREProjectManager,
        subscription_name: AzureSubscriptionName,
    ) -> None:
        self.logger = get_logger()

        self.remote_desktop_output: dict[str, str] = sre_project_manager.output(
            "remote_desktop"
        )
        self.subscription_name = subscription_name

    def run(self) -> None:
        azure_container_instance = AzureContainerInstance(
            container_group_name=self.remote_desktop_output["container_group_name"],
            resource_group_name=self.remote_desktop_output["resource_group_name"],
            subscription_name=self.subscription_name,
        )

        pytest.main(
            args=["--pyargs", "data_safe_haven.healthcheck"],
            plugins=[SREHeathCheckPlugin(azure_container_instance)],
        )
