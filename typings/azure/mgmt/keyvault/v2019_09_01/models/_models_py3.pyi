from typing import Any, Dict, List, Optional, Union
import msrest.serialization
from ._key_vault_management_client_enums import *

class AccessPolicyEntry(msrest.serialization.Model):
    tenant_id: str
    object_id: str
    application_id: str
    permissions: Permissions
    def __init__(
        self,
        *,
        tenant_id: str,
        object_id: str,
        permissions: Permissions,
        application_id: Optional[str] = ...,
        **kwargs: Any
    ) -> None: ...

class IPRule(msrest.serialization.Model):
    def __init__(self, *, value: str, **kwargs: Any) -> None: ...

class NetworkRuleSet(msrest.serialization.Model):
    def __init__(
        self,
        *,
        bypass: Optional[Union[str, NetworkRuleBypassOptions]] = ...,
        default_action: Optional[Union[str, NetworkRuleAction]] = ...,
        ip_rules: Optional[List[IPRule]] = ...,
        virtual_network_rules: Optional[List[VirtualNetworkRule]] = ...,
        **kwargs: Any
    ) -> None: ...

class Permissions(msrest.serialization.Model):
    def __init__(
        self,
        *,
        keys: Optional[List[Union[str, KeyPermissions]]] = ...,
        secrets: Optional[List[Union[str, SecretPermissions]]] = ...,
        certificates: Optional[List[Union[str, CertificatePermissions]]] = ...,
        storage: Optional[List[Union[str, StoragePermissions]]] = ...,
        **kwargs: Any
    ) -> None: ...

class Sku(msrest.serialization.Model):
    def __init__(
        self,
        *,
        family: Union[str, SkuFamily] = ...,
        name: Union[str, SkuName],
        **kwargs: Any
    ) -> None: ...

class Vault(msrest.serialization.Model):
    id: str
    name: str
    type: str
    location: str
    tags: Dict[str, str]
    properties: VaultProperties

    def __init__(
        self,
        *,
        properties: VaultProperties,
        location: Optional[str] = ...,
        tags: Optional[Dict[str, str]] = ...,
        **kwargs: Any
    ) -> None: ...

class VaultCreateOrUpdateParameters(msrest.serialization.Model):
    def __init__(
        self,
        *,
        location: str,
        properties: VaultProperties,
        tags: Optional[Dict[str, str]] = ...,
        **kwargs: Any
    ) -> None: ...

class VaultProperties(msrest.serialization.Model):
    def __init__(
        self,
        *,
        tenant_id: str,
        sku: Sku,
        access_policies: Optional[List[AccessPolicyEntry]] = ...,
        vault_uri: Optional[str] = ...,
        enabled_for_deployment: Optional[bool] = ...,
        enabled_for_disk_encryption: Optional[bool] = ...,
        enabled_for_template_deployment: Optional[bool] = ...,
        enable_soft_delete: Optional[bool] = ...,
        soft_delete_retention_in_days: Optional[int] = ...,
        enable_rbac_authorization: Optional[bool] = ...,
        create_mode: Optional[Union[str, CreateMode]] = ...,
        enable_purge_protection: Optional[bool] = ...,
        network_acls: Optional[NetworkRuleSet] = ...,
        provisioning_state: Optional[Union[str, VaultProvisioningState]] = ...,
        **kwargs: Any
    ) -> None: ...

class VirtualNetworkRule(msrest.serialization.Model):
    def __init__(
        self,
        *,
        id: str,
        ignore_missing_vnet_service_endpoint: Optional[bool] = ...,
        **kwargs: Any
    ) -> None: ...
