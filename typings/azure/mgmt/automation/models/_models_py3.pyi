from typing import Any, Dict, List, Optional
from ._automation_client_enums import ModuleProvisioningState
import msrest.serialization

class DscCompilationJob(Resource):
    id: str
    name: str
    type: str
    configuration: DscConfigurationAssociationProperty
    started_by: str
    job_id: str
    creation_time: str
    provisioning_state: str
    run_on: str
    status: str
    status_details: str
    start_time: str
    end_time: str
    exception: str
    last_modified_time: str
    last_status_modified_time: str
    parameters: Dict[str, Any]
    def __init__(self, kwargs: Any) -> None: ...

class DscCompilationJobCreateParameters(msrest.serialization.Model):
    def __init__(
        self,
        name: Optional[str] = None,
        location: Optional[str] = None,
        tags: Optional[Dict[str, Any]] = None,
        configuration: Optional[DscConfigurationAssociationProperty] = None,
        parameters: Optional[Dict[str, Any]] = None,
        increment_node_configuration_build: Optional[bool] = None,
    ) -> None: ...

class DscConfigurationAssociationProperty(msrest.serialization.Model):
    def __init__(
        self,
        name: Optional[str] = None,
    ) -> None: ...

class Module(TrackedResource):
    name: str
    provisioning_state: str | ModuleProvisioningState

    def __init__(self, *args: Any, **kwargs: Any) -> None: ...

class Resource(msrest.serialization.Model):
    def __init__(self, **kwargs: Any) -> None: ...

class TrackedResource(Resource):
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
