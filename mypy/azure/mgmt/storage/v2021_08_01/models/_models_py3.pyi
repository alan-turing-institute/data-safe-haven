from typing import Any, Dict, List, Optional
import msrest.serialization
from _typeshed import Incomplete

class StorageAccountKey(msrest.serialization.Model):
    key_name: Incomplete
    value: str
    permissions: Incomplete
    creation_time: Incomplete
    def __init__(self, **kwargs) -> None: ...

class StorageAccountListKeysResult(msrest.serialization.Model):
    keys: Optional[List[StorageAccountKey]]
    def __init__(self, **kwargs) -> None: ...

class Resource(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...

class StorageAccount(TrackedResource):
    name: str
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...

class StorageAccountCreateParameters(msrest.serialization.Model):
    def __init__(
        self,
        *,
        sku: "Sku",
        kind: Union[str, "Kind"],
        location: str,
        extended_location: Optional["ExtendedLocation"] = None,
        tags: Optional[Dict[str, str]] = None,
        identity: Optional["Identity"] = None,
        allowed_copy_scope: Optional[Union[str, "AllowedCopyScope"]] = None,
        public_network_access: Optional[Union[str, "PublicNetworkAccess"]] = None,
        sas_policy: Optional["SasPolicy"] = None,
        key_policy: Optional["KeyPolicy"] = None,
        custom_domain: Optional["CustomDomain"] = None,
        encryption: Optional["Encryption"] = None,
        network_rule_set: Optional["NetworkRuleSet"] = None,
        access_tier: Optional[Union[str, "AccessTier"]] = None,
        azure_files_identity_based_authentication: Optional[
            "AzureFilesIdentityBasedAuthentication"
        ] = None,
        enable_https_traffic_only: Optional[bool] = None,
        is_sftp_enabled: Optional[bool] = None,
        is_local_user_enabled: Optional[bool] = None,
        is_hns_enabled: Optional[bool] = None,
        large_file_shares_state: Optional[Union[str, "LargeFileSharesState"]] = None,
        routing_preference: Optional["RoutingPreference"] = None,
        allow_blob_public_access: Optional[bool] = None,
        minimum_tls_version: Optional[Union[str, "MinimumTlsVersion"]] = None,
        allow_shared_key_access: Optional[bool] = None,
        enable_nfs_v3: Optional[bool] = None,
        allow_cross_tenant_replication: Optional[bool] = None,
        default_to_o_auth_authentication: Optional[bool] = None,
        immutable_storage_with_versioning: Optional["ImmutableStorageAccount"] = None,
        **kwargs: Any
    ) -> None: ...

class TrackedResource(Resource):
    def __init__(
        self, *, location: str, tags: Optional[Dict[str, str]] = None, **kwargs
    ) -> None: ...
