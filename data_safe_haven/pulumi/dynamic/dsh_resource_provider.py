"""Pulumi base dynamic component."""
# Standard library imports
from collections.abc import Sequence
from typing import Any, Dict

# Third party imports
from pulumi.dynamic import (
    CheckResult,
    CreateResult,
    DiffResult,
    ReadResult,
    ResourceProvider,
    UpdateResult,
)

# Local imports
from data_safe_haven.exceptions import DataSafeHavenNotImplementedException


class DshResourceProvider(ResourceProvider):
    @staticmethod
    def partial_diff(
        old_props: dict[str, Any],
        new_props: dict[str, Any],
        excluded_props: Sequence[str] = [],
    ) -> DiffResult:
        """Calculate diff between old and new state"""
        # List any values that were not present in old_props or have been changed
        # Exclude any from excluded_props which should not trigger a diff
        altered_props = [
            property
            for property in [key for key in new_props.keys() if key not in excluded_props]
            if (property not in old_props) or (old_props[property] != new_props[property])
        ]
        stable_props = [property for property in old_props.keys() if property not in altered_props]
        return DiffResult(
            changes=(altered_props != []),  # changes are needed
            replaces=altered_props,  # properties that cannot be updated in-place
            stables=stable_props,  # properties that will not change on update
            delete_before_replace=True,  # delete the existing resource before replacing
        )

    @staticmethod
    def refresh(props: dict[str, Any]) -> dict[str, Any]:
        return dict(**props)

    def check(self, old_props: dict[str, Any], new_props: dict[str, Any]) -> CheckResult:
        """Validate that the new properties are valid"""
        return CheckResult(self.refresh(new_props), [])

    def create(self, props: dict[str, Any]) -> CreateResult:
        """Create compiled desired state file."""
        msg = "DshResourceProvider::create() must be implemented"
        raise DataSafeHavenNotImplementedException(msg)

    def delete(self, id_: str, props: dict[str, Any]) -> None:
        """Delete the resource."""
        msg = "DshResourceProvider::delete() must be implemented"
        raise DataSafeHavenNotImplementedException(msg)

    def diff(
        self,
        id_: str,
        old_props: dict[str, Any],
        new_props: dict[str, Any],
    ) -> DiffResult:
        msg = "DshResourceProvider::diff() must be implemented"
        raise DataSafeHavenNotImplementedException(msg)

    def read(self, id_: str, props: dict[str, Any]) -> ReadResult:
        """Read data for a resource not managed by Pulumi."""
        props = self.refresh(props)
        return ReadResult(id_, props)

    def update(
        self,
        id_: str,
        old_props: dict[str, Any],
        new_props: dict[str, Any],
    ) -> UpdateResult:
        """Updating is deleting followed by creating."""
        self.delete(id_, old_props)
        updated = self.create(new_props)
        return UpdateResult(outs=updated.outs)
