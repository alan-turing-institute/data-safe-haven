"""Pulumi dynamic component for running remote scripts on an Azure VM."""
from typing import Any

from pulumi import Input, Output, ResourceOptions
from pulumi.dynamic import CreateResult, DiffResult, Resource

from data_safe_haven.external import AzureApi

from .dsh_resource_provider import DshResourceProvider


class RemoteScriptProps:
    """Props for the RemoteScript class"""

    def __init__(
        self,
        script_contents: Input[str],
        script_hash: Input[str],
        script_parameters: Input[dict[str, Any]],
        subscription_name: Input[str],
        vm_name: Input[str],
        vm_resource_group_name: Input[str],
        force_refresh: Input[bool] | None,
    ) -> None:
        self.force_refresh = force_refresh
        self.script_contents = script_contents
        self.script_hash = script_hash
        self.script_parameters = script_parameters
        self.subscription_name = subscription_name
        self.vm_name = vm_name
        self.vm_resource_group_name = vm_resource_group_name


class RemoteScriptProvider(DshResourceProvider):
    def create(self, props: dict[str, Any]) -> CreateResult:
        """Create compiled desired state file."""
        outs = dict(**props)
        azure_api = AzureApi(props["subscription_name"], disable_logging=True)
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

    def delete(self, id_: str, props: dict[str, Any]) -> None:
        """The Python SDK does not support configuration deletion"""
        # Use `id` as a no-op to avoid ARG002 while maintaining function signature
        id((id_, props))

    def diff(
        self,
        id_: str,
        old_props: dict[str, Any],
        new_props: dict[str, Any],
    ) -> DiffResult:
        """Calculate diff between old and new state"""
        # Use `id` as a no-op to avoid ARG002 while maintaining function signature
        id(id_)
        if new_props["force_refresh"]:
            return DiffResult(
                changes=True,
                replaces=list(new_props.keys()),
                stables=[],
                delete_before_replace=True,
            )
        return self.partial_diff(old_props, new_props, [])


class RemoteScript(Resource):
    script_output: Output[str]
    _resource_type_name = "dsh:RemoteScript"  # set resource type

    def __init__(
        self,
        name: str,
        props: RemoteScriptProps,
        opts: ResourceOptions | None = None,
    ):
        super().__init__(
            RemoteScriptProvider(), name, {"script_output": None, **vars(props)}, opts
        )
