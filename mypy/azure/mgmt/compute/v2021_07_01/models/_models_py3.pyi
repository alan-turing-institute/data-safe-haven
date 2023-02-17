from typing import Any, List, Optional

from ... import _serialization

class ResourceSku(_serialization.Model):
    resource_type: Optional[str] = None
    name: Optional[str] = None
    tier: Optional[str] = None
    size: Optional[str] = None
    family: Optional[str] = None
    kind: Optional[str] = None
    capacity: Optional[ResourceSkuCapacity] = None
    locations: Optional[List[str]] = None
    location_info: Optional[List[ResourceSkuLocationInfo]] = None
    api_versions: Optional[List[str]] = None
    costs: Optional[List[ResourceSkuCosts]] = None
    capabilities: Optional[List[ResourceSkuCapabilities]] = None
    restrictions: Optional[List[ResourceSkuRestrictions]] = None
    def __init__(self, **kwargs: Any) -> None: ...

class ResourceSkuCapabilities(_serialization.Model):
    name: Optional[str] = None
    value: Optional[str] = None
    def __init__(self, **kwargs: Any) -> None: ...

class ResourceSkuCapacity(_serialization.Model):
    minimum: Optional[int] = None
    maximum: Optional[int] = None
    default: Optional[int] = None
    scale_type: Optional[str] = None
    def __init__(self, **kwargs: Any) -> None: ...

class ResourceSkuCosts(_serialization.Model):
    meter_id: Optional[str] = None
    quantity: Optional[int] = None
    extended_unit: Optional[str] = None
    def __init__(self, **kwargs: Any) -> None: ...

class ResourceSkuLocationInfo(_serialization.Model):
    location: Optional[str] = None
    zones: Optional[List[str]] = None
    zone_details: Optional[List[ResourceSkuZoneDetails]] = None
    extended_locations: Optional[List[str]] = None
    type: Optional[str] = None
    def __init__(self, **kwargs: Any) -> None: ...

class ResourceSkuRestrictionInfo(_serialization.Model):
    locations: Optional[List[str]] = None
    zones: Optional[List[str]] = None
    def __init__(self, **kwargs: Any) -> None: ...

class ResourceSkuRestrictions(_serialization.Model):
    type: Optional[str] = None
    values: Optional[List[str]] = None
    restriction_info: Optional[ResourceSkuRestrictionInfo] = None
    reason_code: Optional[str] = None
    def __init__(self, **kwargs: Any) -> None: ...

class ResourceSkuZoneDetails(_serialization.Model):
    name: Optional[List[str]] = None
    capabilities: Optional[List[ResourceSkuCapabilities]] = None
    def __init__(self, **kwargs: Any) -> None: ...
