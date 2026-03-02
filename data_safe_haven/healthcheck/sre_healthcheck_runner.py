import pytest

from data_safe_haven.config import SREConfig
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
        sre_config: SREConfig,
        verbose: bool,  # noqa: FBT001
    ) -> None:
        self.logger = get_logger()

        self.sre_project_manager = sre_project_manager
        self.subscription_name = subscription_name
        self.sre_config = sre_config
        self.verbose = verbose

    def run(self) -> None:
        healthcheck_plugin = SREHeathCheckPlugin(
            self.sre_project_manager, self.subscription_name, self.sre_config
        )
        pytest_args: list[str] = ["--pyargs", "data_safe_haven.healthcheck"]
        if not self.verbose:
            pytest_args.append("--tb=line")

        pytest.main(
            args=pytest_args,
            plugins=[healthcheck_plugin],
        )
