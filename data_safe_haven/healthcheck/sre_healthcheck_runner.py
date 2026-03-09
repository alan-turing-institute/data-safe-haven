from attrs import define

from data_safe_haven.config import SREConfig
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.types import AzureSubscriptionName

from .healthcheck_plugin import SREHeathCheckPlugin
from .test_container_instance import TestContainerInstance


@define
class SREHealthCheckRunner:
    """Healthcheck manager for a deployed SRE"""

    _sre_project_manager: SREProjectManager
    _subscription_name: AzureSubscriptionName
    _sre_config: SREConfig
    _verbose: bool

    def run(self) -> None:

        test_container_instances = TestContainerInstance(
            SREHeathCheckPlugin(
                self._sre_project_manager, self._subscription_name, self._sre_config
            )
        )

        test_container_instances.test_container_state(
            output_keys=[
                "apt_proxy_server",
                "sre_clamav_mirror",
                "sre_gitea_server",
                "remote_desktop",
                "sre_hedgedoc_server",
                "sre_identity",
            ]
        )
        test_container_instances.test_software_repositories_container()
