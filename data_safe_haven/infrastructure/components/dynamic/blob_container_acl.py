"""Pulumi dynamic component for setting ACLs on an Azure blob container."""

from typing import Any

from pulumi import Input, Output, ResourceOptions
from pulumi.dynamic import CreateResult, DiffResult, Resource

from data_safe_haven.exceptions import DataSafeHavenPulumiError
from data_safe_haven.external import AzureSdk

from .dsh_resource_provider import DshResourceProvider


class BlobContainerAclProps:
    """Props for the BlobContainerAcl class"""

    def __init__(
        self,
        *,
        acl_user: Input[str],
        acl_group: Input[str],
        acl_other: Input[str],
        apply_default_permissions: bool,
        container_name: Input[str],
        resource_group_name: Input[str],
        storage_account_name: Input[str],
        subscription_name: Input[str],
    ) -> None:
        self.container_name = container_name
        acl_arguments = [
            "user::",
            acl_user,
            ",group::",
            acl_group,
            ",other::",
            acl_other,
        ]
        if apply_default_permissions:
            acl_arguments += [
                ",default:user::",
                acl_user,
                ",default:group::",
                acl_group,
                ",default:other::",
                acl_other,
            ]
        self.desired_acl = Output.concat(*acl_arguments)
        self.resource_group_name = resource_group_name
        self.storage_account_name = storage_account_name
        self.subscription_name = subscription_name


class BlobContainerAclProvider(DshResourceProvider):
    def create(self, props: dict[str, Any]) -> CreateResult:
        """Set ACLs for a given blob container."""
        outs = dict(**props)
        try:
            azure_sdk = AzureSdk(props["subscription_name"], disable_logging=True)
            azure_sdk.set_blob_container_acl(
                container_name=props["container_name"],
                desired_acl=props["desired_acl"],
                resource_group_name=props["resource_group_name"],
                storage_account_name=props["storage_account_name"],
            )
        except Exception as exc:
            msg = f"Failed to set ACLs on storage account '{props['storage_account_name']}'."
            raise DataSafeHavenPulumiError(msg) from exc
        return CreateResult(
            f"BlobContainerAcl-{props['container_name']}",
            outs=outs,
        )

    def delete(self, id_: str, props: dict[str, Any]) -> None:
        """Restore default ACLs"""
        # Use `id` as a no-op to avoid ARG002 while maintaining function signature
        id(id_)
        try:
            azure_sdk = AzureSdk(props["subscription_name"], disable_logging=True)
            azure_sdk.set_blob_container_acl(
                container_name=props["container_name"],
                desired_acl="user::rwx,group::r-x,other::---",
                resource_group_name=props["resource_group_name"],
                storage_account_name=props["storage_account_name"],
            )
        except Exception as exc:
            msg = f"Failed to delete custom ACLs on storage account '{props['storage_account_name']}'."
            raise DataSafeHavenPulumiError(msg) from exc

    def diff(
        self,
        id_: str,
        old_props: dict[str, Any],
        new_props: dict[str, Any],
    ) -> DiffResult:
        """Calculate diff between old and new state"""
        # Use `id` as a no-op to avoid ARG002 while maintaining function signature
        id(id_)
        return self.partial_diff(old_props, new_props)

    def refresh(self, props: dict[str, Any]) -> dict[str, Any]:
        """TODO: check whether ACLs have changed"""
        return dict(**props)


class BlobContainerAcl(Resource):
    _resource_type_name = "dsh:common:BlobContainerAcl"  # set resource type

    def __init__(
        self,
        name: str,
        props: BlobContainerAclProps,
        opts: ResourceOptions | None = None,
    ):
        super().__init__(BlobContainerAclProvider(), name, vars(props), opts)
