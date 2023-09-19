"""Pulumi dynamic component for running remote scripts on an Azure VM."""
from typing import Any

from pulumi import Input, Output, ResourceOptions
from pulumi.dynamic import CreateResult, DiffResult, Resource

from data_safe_haven.external import AzureApi
from data_safe_haven.functions import b64encode

from .dsh_resource_provider import DshResourceProvider


class FileUploadProps:
    """Props for the FileUpload class"""

    def __init__(
        self,
        file_contents: Input[str],
        file_hash: Input[str],
        file_permissions: Input[str],
        file_target: Input[str],
        subscription_name: Input[str],
        vm_name: Input[str],
        vm_resource_group_name: Input[str],
        force_refresh: Input[bool] | None = None,
    ) -> None:
        self.file_contents = file_contents
        self.file_hash = file_hash
        self.file_target = file_target
        self.file_permissions = file_permissions
        self.force_refresh = force_refresh
        self.subscription_name = subscription_name
        self.vm_name = vm_name
        self.vm_resource_group_name = vm_resource_group_name


class FileUploadProvider(DshResourceProvider):
    def create(self, props: dict[str, Any]) -> CreateResult:
        """Run a remote script to create a file on a VM"""
        outs = dict(**props)
        azure_api = AzureApi(props["subscription_name"], disable_logging=True)
        script_contents = f"""
        target_dir=$(dirname "$target");
        mkdir -p $target_dir 2> /dev/null;
        echo $contents_b64 | base64 --decode > $target;
        chmod {props['file_permissions']} $target;
        echo "Wrote file to $target";
        """
        script_parameters = {
            "contents_b64": b64encode(props["file_contents"]),
            "target": props["file_target"],
        }
        # Run remote script
        outs["script_output"] = azure_api.run_remote_script(
            props["vm_resource_group_name"],
            script_contents,
            script_parameters,
            props["vm_name"],
        )
        return CreateResult(
            f"FileUpload-{props['file_hash']}",
            outs=outs,
        )

    def delete(self, id_: str, props: dict[str, Any]) -> None:
        """Delete the remote file from the VM"""
        # Use `id` as a no-op to avoid ARG002 while maintaining function signature
        id((id_, props))
        outs = dict(**props)
        azure_api = AzureApi(props["subscription_name"], disable_logging=True)
        script_contents = """
        rm -f "$target";
        echo "Removed file at $target";
        """
        script_parameters = {
            "target": props["file_target"],
        }
        # Run remote script
        outs["script_output"] = azure_api.run_remote_script(
            props["vm_resource_group_name"],
            script_contents,
            script_parameters,
            props["vm_name"],
        )

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


class FileUpload(Resource):
    script_output: Output[str]
    _resource_type_name = "dsh:common:FileUpload"  # set resource type

    def __init__(
        self,
        name: str,
        props: FileUploadProps,
        opts: ResourceOptions | None = None,
    ):
        super().__init__(
            FileUploadProvider(), name, {"script_output": None, **vars(props)}, opts
        )
