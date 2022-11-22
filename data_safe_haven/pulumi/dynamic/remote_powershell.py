"""Pulumi dynamic component for running remote scripts on an Azure VM."""
# Standard library imports
from typing import Dict, Optional

# Third party imports
from pulumi import Input, Output, ResourceOptions
from pulumi.dynamic import CreateResult, DiffResult, Resource

# Local imports
from data_safe_haven.external.api import AzureApi
from .dsh_resource_provider import DshResourceProvider


class RemoteScriptProps:
    """Props for the RemoteScript class"""

    def __init__(
        self,
        script_contents: Input[str],
        script_hash: Input[str],
        script_parameters: Input[str],
        subscription_name: Input[str],
        vm_name: Input[str],
        vm_resource_group_name: Input[str],
    ):
        self.script_contents = script_contents
        self.script_hash = script_hash
        self.script_parameters = script_parameters
        self.subscription_name = subscription_name
        self.vm_name = vm_name
        self.vm_resource_group_name = vm_resource_group_name


class RemoteScriptProvider(DshResourceProvider):
    def create(self, props: Dict[str, str]) -> CreateResult:
        """Create compiled desired state file."""
        outs = dict(**props)
        azure_api = AzureApi(props["subscription_name"])
        # Run remote script
        outs["script_output"] = azure_api.run_remote_script(
            props["vm_resource_group_name"],
            props["script_contents"],
            props["script_parameters"],
            props["vm_name"],
        )
        return CreateResult(
            f"RemoteScript-{props['script_hash']}",
            outs=outs,
        )

    def delete(self, id: str, props: Dict[str, str]) -> None:
        """The Python SDK does not support configuration deletion"""
        return

    def diff(
        self,
        id_: str,
        old_props: Dict[str, str],
        new_props: Dict[str, str],
    ) -> DiffResult:
        """Calculate diff between old and new state"""
        return self.partial_diff(old_props, new_props, [])


class RemoteScript(Resource):
    script_output: Output[str]

    def __init__(
        self,
        name: str,
        props: RemoteScriptProps,
        opts: Optional[ResourceOptions] = None,
    ):
        self._resource_type_name = "dsh:RemoteScript"  # set resource type
        super().__init__(
            RemoteScriptProvider(), name, {"script_output": None, **vars(props)}, opts
        )
