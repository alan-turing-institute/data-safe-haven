from abc import ABC, abstractmethod
from typing import ClassVar

from data_safe_haven.types import AzureSubscriptionName, EntraGroupName


class ContextBase(ABC):
    admin_group_name: EntraGroupName
    subscription_name: AzureSubscriptionName
    storage_container_name: ClassVar[str]

    @property
    @abstractmethod
    def resource_group_name(self) -> str:
        pass

    @property
    @abstractmethod
    def storage_account_name(self) -> str:
        pass
