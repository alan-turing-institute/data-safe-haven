from typing import Any
import msrest.serialization
from _typeshed import Incomplete

class Resource(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...

class ProxyResource(Resource):
    def __init__(self, **kwargs: Any) -> None: ...

class FirewallRule(ProxyResource):
    def __init__(self, **kwargs: Any) -> None: ...

class ResourceIdentity(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...

class TrackedResource(Resource):
    def __init__(self, **kwargs: Any) -> None: ...

class Server(TrackedResource):
    id: str
    name: str
    type: str
    tags: Incomplete
    location: str
    identity: ResourceIdentity
    sku: Sku
    administrator_login: str
    version: str
    ssl_enforcement: str
    minimal_tls_version: str
    byok_enforcement: str
    infrastructure_encryption: str
    user_visible_state: str
    fully_qualified_domain_name: str
    earliest_restore_date: str
    storage_profile: Incomplete
    replication_role: str
    master_server_id: str
    replica_capacity: str
    public_network_access: str
    private_endpoint_connections: Incomplete
    def __init__(self, **kwargs: Any) -> None: ...

class ServerUpdateParameters(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...

class Sku(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...
