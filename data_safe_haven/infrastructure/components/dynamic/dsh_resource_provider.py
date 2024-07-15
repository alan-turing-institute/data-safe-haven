"""Pulumi base dynamic component."""

from abc import ABCMeta, abstractmethod
from collections.abc import Sequence
from typing import Any

from pulumi.dynamic import (
    CheckResult,
    CreateResult,
    DiffResult,
    ReadResult,
    ResourceProvider,
    UpdateResult,
)


class DshResourceProvider(ResourceProvider, metaclass=ABCMeta):
    @staticmethod
    def partial_diff(
        old_props: dict[str, Any],
        new_props: dict[str, Any],
        excluded_props: Sequence[str] = [],
    ) -> DiffResult:
        """
        Calculate a diff between an old and new set of props, excluding any if requested.

        Args:
            old_props: the outputs from the last create operation
            new_props: a set of checked inputs
            excluded_props: any props to exclude from the comparison

        Returns:
            DiffResult:
                - changes: whether any non-excluded props have changed
                - replaces: any non-excluded props that have changed
                - stables: any properties that are excluded or unchanged
                - delete_before_replace: True
        """
        # List any values that were not present in old_props or have been changed
        # Exclude any from excluded_props which should not trigger a diff
        altered_props = [
            property_
            for property_ in [
                key for key in new_props.keys() if key not in excluded_props
            ]
            if (property_ not in old_props)
            or (old_props[property_] != new_props[property_])
        ]
        stable_props = [
            property_
            for property_ in old_props.keys()
            if property_ not in altered_props
        ]
        return DiffResult(
            changes=(altered_props != []),  # changes are needed
            replaces=altered_props,  # properties that cannot be updated in-place
            stables=stable_props,  # properties that will not change on update
            delete_before_replace=True,  # delete the existing resource before replacing
        )

    def check(
        self, old_props: dict[str, Any], new_props: dict[str, Any]
    ) -> CheckResult:
        """
        Invoked on update before any other method.
        Verify that the props are valid or return useful error messages if they are not.

        Returns:
            CheckResult: a set of checked inputs together with any failures
        """
        # Ensure that old props are up-to-date
        props = self.refresh(old_props)
        # Overwrite with any changes from new props
        props.update(new_props)
        return CheckResult(props, [])

    @abstractmethod
    def create(self, props: dict[str, Any]) -> CreateResult:
        """
        Invoked when the desired resource is not found in the existing state.

        Args:
            props: a set of checked inputs

        Returns:
            CreateResult: a unique ID for this object plus a set of output properties
        """

    @abstractmethod
    def delete(self, id_: str, old_props: dict[str, Any]) -> None:
        """
        Invoked when the desired resource is found in the existing state but is not wanted.

        Args:
            id_: the ID of the resource
            old_props: the outputs from the last create operation
        """

    @abstractmethod
    def diff(
        self,
        id_: str,
        old_props: dict[str, Any],
        new_props: dict[str, Any],
    ) -> DiffResult:
        """
        Invoked when the desired resource is found in the existing state.

        Args:
            id_: the ID of the resource
            old_props: the outputs from the last create operation
            new_props: a set of checked inputs

        Returns:
            DiffResult:
                - changes: whether changes are needed
                - replaces: any changed properties that mean a replacement is needed instead of an update
                - stables: any properties that have not changed
                - delete_before_replace: whether to delete the old object before creating the new one
        """

    def read(self, id_: str, props: dict[str, Any]) -> ReadResult:
        """
        Invoked when Pulumi needs to get data about a non-managed resource

        Args:
            id_: the ID of the resource
            props: a set of checked inputs used to disambiguate the request

        Returns:
            CreateResult: a unique ID for this object plus a set of output properties
        """
        return ReadResult(id_, self.refresh(props))

    @abstractmethod
    def refresh(self, props: dict[str, Any]) -> dict[str, Any]:
        """
        Given a set of props, check whether these are still correct.

        Returns:
            dict[str, Any]: a set of props that represent the current state of the remote object
        """
        return dict(**props)

    def update(
        self,
        id_: str,
        old_props: dict[str, Any],
        new_props: dict[str, Any],
    ) -> UpdateResult:
        """
        Invoked when the desired resource needs a change but not a replacement.

        Args:
            id_: the ID of the resource
            old_props: the outputs from the last create operation
            new_props: a set of checked inputs

        Returns:
            UpdateResult: a set of output properties
        """
        self.delete(id_, old_props)
        updated = self.create(new_props)
        return UpdateResult(outs=updated.outs)
