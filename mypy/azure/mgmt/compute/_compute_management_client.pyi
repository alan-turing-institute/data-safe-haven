from typing import Any, Optional

from azure.core.credentials import TokenCredential
from azure.identity import DefaultAzureCredential
from azure.profiles import KnownProfiles
from azure.profiles.multiapiclient import MultiApiClientMixin
from .v2021_07_01.operations import ResourceSkusOperations
from .v2022_11_01.operations import VirtualMachinesOperations

class _SDKClient(object):
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...

class ComputeManagementClient(MultiApiClientMixin, _SDKClient):
    def __init__(
        self,
        credential: TokenCredential | DefaultAzureCredential,
        subscription_id: str,
        api_version: Optional[str] = None,
        base_url: Optional[str] = ...,
        profile: Optional[KnownProfiles] = ...,
        **kwargs: Any
    ) -> None: ...
    @property
    def resource_skus(self) -> ResourceSkusOperations: ...
    @property
    def virtual_machines(self) -> VirtualMachinesOperations: ...
