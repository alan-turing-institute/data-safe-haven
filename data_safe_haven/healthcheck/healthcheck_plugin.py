from attrs import define
from pytest import fixture

from data_safe_haven.external import AzureContainerInstance
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.types import AzureSubscriptionName


@define(frozen=True)
class SREHeathCheckPlugin:

    _sre_project_manager: SREProjectManager
    _subscription_name: AzureSubscriptionName

    @fixture
    def remote_desktop_container_instance(self) -> AzureContainerInstance:
        remote_desktop_output: dict[str, str] = self._sre_project_manager.output(
            "remote_desktop"
        )
        azure_container_instance = AzureContainerInstance(
            container_group_name=remote_desktop_output["container_group_name"],
            resource_group_name=remote_desktop_output["resource_group_name"],
            subscription_name=self._subscription_name,
        )

        return azure_container_instance
