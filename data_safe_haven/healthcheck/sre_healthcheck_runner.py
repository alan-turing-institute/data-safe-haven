import logging

from attrs import define

from data_safe_haven.config import SREConfig
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.types import AzureSubscriptionName

from .healthcheck_plugin import SREHeathCheckPlugin
from .healthcheck_utils import HealthCheckError, HealthCheckTest
from .test_container_instance import (
    CheckContainerInstance,
    CheckSoftwareRepositoriesContainer,
)


@define
class SREHealthCheckRunner:
    """Healthcheck manager for a deployed SRE"""

    _logger: logging.Logger
    _sre_project_manager: SREProjectManager
    _subscription_name: AzureSubscriptionName
    _sre_config: SREConfig
    _verbose: bool

    def run(self) -> None:

        health_check_plugin = SREHeathCheckPlugin(
            self._sre_project_manager, self._subscription_name, self._sre_config
        )

        test_classes: list[HealthCheckTest] = [
            CheckSoftwareRepositoriesContainer(),
        ]
        test_classes += [
            CheckContainerInstance(output_key=output_key)
            for output_key in [
                "apt_proxy_server",
                "sre_clamav_mirror",
                "sre_gitea_server",
                "remote_desktop",
                "sre_hedgedoc_server",
                "sre_identity",
            ]
        ]

        for health_check in test_classes:
            try:
                success_message = health_check.check(health_check_plugin)
                self._logger.info(f"\u2705 {success_message}")
            except HealthCheckError as error:
                self._logger.info(f"\u274c {error.args[0]}")
