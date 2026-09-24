from attrs import define

from data_safe_haven.config import SREConfig
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.types import AzureSubscriptionName


@define
class SREHeathCheckPlugin:

    _sre_project_manager: SREProjectManager
    _subscription_name: AzureSubscriptionName
    _sre_config: SREConfig

    @property
    def project_manager(self) -> SREProjectManager:
        return self._sre_project_manager

    @property
    def subscription_name(self) -> AzureSubscriptionName:
        return self._subscription_name

    @property
    def sre_config(self) -> SREConfig:
        return self._sre_config
