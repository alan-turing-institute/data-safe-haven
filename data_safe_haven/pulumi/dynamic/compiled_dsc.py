"""Pulumi dynamic component for compiled desired state configuration."""
# Standard library imports
from collections.abc import Sequence
from typing import Any, Dict, Optional

# Third party imports
from pulumi import Input, ResourceOptions
from pulumi.dynamic import CreateResult, DiffResult, Resource

# Local imports
from data_safe_haven.external import AzureApi
from data_safe_haven.pulumi.dynamic.dsh_resource_provider import DshResourceProvider


class CompiledDscProps:
    """Props for the CompiledDsc class"""

    def __init__(
        self,
        automation_account_name: Input[str],
        configuration_name: Input[str],
        content_hash: Input[str],
        location: Input[str],
        parameters: Input[dict[str, Any]],
        resource_group_name: Input[str],
        required_modules: Input[Sequence[str]],
        subscription_name: Input[str],
    ):
        self.automation_account_name = automation_account_name
        self.configuration_name = configuration_name
        self.content_hash = content_hash
        self.location = location
        self.parameters = parameters
        self.resource_group_name = resource_group_name
        self.required_modules = required_modules
        self.subscription_name = subscription_name


class CompiledDscProvider(DshResourceProvider):
    def create(self, props: dict[str, Any]) -> CreateResult:
        """Create compiled desired state file."""
        azure_api = AzureApi(props["subscription_name"])
        # Compile desired state
        azure_api.compile_desired_state(
            automation_account_name=props["automation_account_name"],
            configuration_name=props["configuration_name"],
            location=props["location"],
            parameters=props["parameters"],
            resource_group_name=props["resource_group_name"],
            required_modules=props["required_modules"],
        )
        return CreateResult(
            f"CompiledDsc-{props['configuration_name']}",
            outs=dict(**props),
        )

    def delete(self, id_: str, props: dict[str, Any]) -> None:
        """The Python SDK does not support configuration deletion"""
        return

    def diff(
        self,
        id_: str,
        old_props: dict[str, Any],
        new_props: dict[str, Any],
    ) -> DiffResult:
        """Calculate diff between old and new state"""
        return self.partial_diff(old_props, new_props, [])


class CompiledDsc(Resource):
    _resource_type_name = "dsh:CompiledDsc"  # set resource type

    def __init__(
        self,
        name: str,
        props: CompiledDscProps,
        opts: ResourceOptions | None = None,
    ):
        super().__init__(CompiledDscProvider(), name, {**vars(props)}, opts)
