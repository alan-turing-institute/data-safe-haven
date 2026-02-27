from attrs import define
from pytest import fixture

from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.types import AzureSubscriptionName


@define(frozen=True)
class SREHeathCheckPlugin:

    _sre_project_manager: SREProjectManager
    _subscription_name: AzureSubscriptionName

    @fixture
    def project_manager(self) -> SREProjectManager:
        return self._sre_project_manager

    @fixture
    def subscription_name(self) -> AzureSubscriptionName:
        return self._subscription_name
