from attrs import define
from pytest import fixture

from data_safe_haven.external import AzureContainerInstance


@define(frozen=True)
class SREHeathCheckPlugin:

    _azure_container_instance: AzureContainerInstance

    @fixture
    def azure_container_instance(self) -> AzureContainerInstance:
        return self._azure_container_instance
