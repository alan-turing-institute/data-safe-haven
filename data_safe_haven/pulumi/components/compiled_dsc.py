# Standard library imports
import binascii
import os
from typing import Optional

# Third party imports
from pulumi import Input, ResourceOptions
from pulumi.dynamic import (
    Resource,
    ResourceProvider,
    CreateResult,
    DiffResult,
    UpdateResult,
)

# Local imports
from data_safe_haven.helpers import AzureApi


class CompiledDscProps:
    """Props for the CompiledDsc class"""

    def __init__(
        self,
        automation_account_name: Input[str],
        configuration_name: Input[str],
        location: Input[str],
        resource_group_name: Input[str],
        subscription_name: Input[str],
    ):
        self.automation_account_name = automation_account_name
        self.configuration_name = configuration_name
        self.location = location
        self.resource_group_name = resource_group_name
        self.subscription_name = subscription_name


class _CompiledDscProps:
    """Unwrapped version of CompiledDscProps"""

    def __init__(
        self,
        automation_account_name: str,
        configuration_name: str,
        location: str,
        resource_group_name: str,
    ):
        self.automation_account_name = automation_account_name
        self.configuration_name = configuration_name
        self.location = location
        self.resource_group_name = resource_group_name


class CompiledDscProvider(ResourceProvider):
    def create(self, props: _CompiledDscProps) -> CreateResult:
        """Compile desired state file."""
        # Apply desired state
        azure_api = AzureApi(props["subscription_name"])
        azure_api.compile_desired_state(
            automation_account_name=props["automation_account_name"],
            configuration_name=props["configuration_name"],
            location=props["location"],
            resource_group_name=props["resource_group_name"],
        )
        return CreateResult(
            f"CompiledDsc-{binascii.b2a_hex(os.urandom(16)).decode('utf-8')}",
            outs={**props},
        )

    def delete(self, id: str, props: _CompiledDscProps) -> None:
        """The Python DSK does not support configuration deletion"""
        pass

    def diff(
        self,
        id: str,
        oldProps: _CompiledDscProps,
        newProps: _CompiledDscProps,
    ) -> DiffResult:
        """As Python DSK does not support configuration deletion we cannot change or replace a configuration"""
        return DiffResult(
            changes=True,  # always mark changes as needed
            replaces=None,  # do not list what
            stables=None,  # list of inputs that are constant
            delete_before_replace=False,  # delete the existing resource before replacing
        )

    def update(
        self,
        id: str,
        oldProps: _CompiledDscProps,
        newProps: _CompiledDscProps,
    ) -> DiffResult:
        """Updating is deleting followed by creating."""
        self.delete(id, oldProps)
        updated = self.create(newProps)
        return UpdateResult(outs={**updated.outs})


class CompiledDsc(Resource):
    def __init__(
        self,
        name: str,
        props: CompiledDscProps,
        opts: Optional[ResourceOptions] = None,
    ):
        self._resource_type_name = "desired_state:CompiledDsc"  # set resource type
        super().__init__(CompiledDscProvider(), name, {**vars(props)}, opts)
