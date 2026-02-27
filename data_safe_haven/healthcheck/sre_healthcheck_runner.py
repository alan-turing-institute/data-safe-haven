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

        self.sre_project_manager = sre_project_manager
        self.subscription_name = subscription_name

    def run(self) -> None:
        healthcheck_plugin = SREHeathCheckPlugin(
            self.sre_project_manager, self.subscription_name
        )
        pytest.main(
            args=["--pyargs", "data_safe_haven.healthcheck", "--tb=line"],
            plugins=[healthcheck_plugin],
        )
