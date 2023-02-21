from typing import Any, Dict, List, Optional, Union
import msrest.serialization
from _typeshed import Incomplete
from ._storage_management_client_enums import *

class AzureEntityResource(Resource):
    def __init__(self, **kwargs: Any) -> None: ...

class BlobContainer(AzureEntityResource):
    id: str
    name: str
    type: str
    etag: str
    version: str
    deleted: bool
    deleted_time: str
    remaining_retention_days: int
    default_encryption_scope: str
    deny_encryption_scope_override: bool
    public_access: str
    last_modified_time: str
    lease_status: str
    lease_state: str
    lease_duration: str
    metadata: Incomplete
    immutability_policy: Incomplete
    legal_hold: Incomplete
    has_legal_hold: bool
    has_immutability_policy: bool
    immutable_storage_with_versioning: ImmutableStorageWithVersioning
    enable_nfs_v3_root_squash: bool
    enable_nfs_v3_all_squash: bool

    def __init__(
        self,
        *,
        default_encryption_scope: Optional[str] = None,
        deny_encryption_scope_override: Optional[bool] = None,
        public_access: Optional[Union[str, PublicAccess]] = None,
        metadata: Optional[Dict[str, str]] = None,
        immutable_storage_with_versioning: Optional[
            ImmutableStorageWithVersioning
        ] = None,
        enable_nfs_v3_root_squash: Optional[bool] = None,
        enable_nfs_v3_all_squash: Optional[bool] = None,
        **kwargs: Any
    ) -> None: ...

class ImmutableStorageWithVersioning(msrest.serialization.Model):
    def __init__(self, *, enabled: Optional[bool] = None, **kwargs: Any) -> None: ...

class Resource(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...

class Sku(msrest.serialization.Model):
    def __init__(self, *, name: Union[str, SkuName], **kwargs: Any) -> None: ...

class StorageAccount(TrackedResource):
    name: str
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...

class StorageAccountCreateParameters(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...

class StorageAccountKey(msrest.serialization.Model):
    key_name: Incomplete
    value: str
    permissions: Incomplete
    creation_time: Incomplete
    def __init__(self, **kwargs: Any) -> None: ...

class StorageAccountListKeysResult(msrest.serialization.Model):
    keys: Optional[List[StorageAccountKey]]
    def __init__(self, **kwargs: Any) -> None: ...

class TrackedResource(Resource):
    def __init__(
        self, *, location: str, tags: Optional[Dict[str, str]] = None, **kwargs: Any
    ) -> None: ...
