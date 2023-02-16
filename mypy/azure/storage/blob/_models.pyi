from enum import Enum
from _typeshed import Incomplete
from azure.core import CaseInsensitiveEnumMeta
from ._shared.models import DictMixin

def parse_page_list(page_list): ...

class BlobType(str, Enum, metaclass=CaseInsensitiveEnumMeta):
    BLOCKBLOB: str
    PAGEBLOB: str
    APPENDBLOB: str

class ContainerProperties(DictMixin):
    name: Incomplete
    last_modified: Incomplete
    etag: Incomplete
    lease: Incomplete
    public_access: Incomplete
    has_immutability_policy: Incomplete
    deleted: Incomplete
    version: Incomplete
    has_legal_hold: Incomplete
    metadata: Incomplete
    encryption_scope: Incomplete
    immutable_storage_with_versioning_enabled: Incomplete
    def __init__(self, **kwargs) -> None: ...

class BlobProperties(DictMixin):
    name: Incomplete
    container: Incomplete
    snapshot: Incomplete
    version_id: Incomplete
    is_current_version: Incomplete
    blob_type: Incomplete
    metadata: Incomplete
    encrypted_metadata: Incomplete
    last_modified: Incomplete
    etag: Incomplete
    size: Incomplete
    content_range: Incomplete
    append_blob_committed_block_count: Incomplete
    is_append_blob_sealed: Incomplete
    page_blob_sequence_number: Incomplete
    server_encrypted: Incomplete
    copy: Incomplete
    content_settings: Incomplete
    lease: Incomplete
    blob_tier: Incomplete
    rehydrate_priority: Incomplete
    blob_tier_change_time: Incomplete
    blob_tier_inferred: Incomplete
    deleted: bool
    deleted_time: Incomplete
    remaining_retention_days: Incomplete
    creation_time: Incomplete
    archive_status: Incomplete
    encryption_key_sha256: Incomplete
    encryption_scope: Incomplete
    request_server_encrypted: Incomplete
    object_replication_source_properties: Incomplete
    object_replication_destination_policy: Incomplete
    last_accessed_on: Incomplete
    tag_count: Incomplete
    tags: Incomplete
    immutability_policy: Incomplete
    has_legal_hold: Incomplete
    has_versions_only: Incomplete
    def __init__(self, **kwargs) -> None: ...
