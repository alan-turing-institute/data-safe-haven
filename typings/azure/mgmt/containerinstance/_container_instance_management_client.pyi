from typing import Any, Optional
from azure.core.credentials import TokenCredential
from .operations import ContainersOperations, ContainerGroupsOperations

class ContainerInstanceManagementClient:
    def __init__(
        self,
        credential: TokenCredential,
        subscription_id: str,
        api_version: Optional[str] = None,
        base_url: Optional[str] = ...,
        **kwargs: Any
    ) -> None: ...
    @property
    def containers(self) -> ContainersOperations: ...
    @property
    def container_groups(self) -> ContainerGroupsOperations: ...
