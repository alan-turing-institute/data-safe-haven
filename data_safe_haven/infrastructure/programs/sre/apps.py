"""Pulumi component for SRE function/web apps"""

from collections.abc import Mapping

from pulumi import ComponentResource, FileArchive, Input, Output, ResourceOptions
from pulumi_azure_native import (
    resources,
    storage,
    web,
)

from data_safe_haven.functions import (
    alphanumeric,
    truncate_tokens,
)
from data_safe_haven.infrastructure.common import (
    get_name_from_rg,
)
from data_safe_haven.resources import resources_path


class SREAppsProps:
    """Properties for SREAppsComponent"""

    def __init__(
        self,
        resource_group: Input[resources.ResourceGroup],
    ):
        self.resource_group_name = Output.from_input(resource_group).apply(
            get_name_from_rg
        )


class SREAppsComponent(ComponentResource):
    """Deploy SRE function/web apps with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREAppsProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:AppsComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Deploy storage account
        # The storage account holds app data/configuration
        storage_account = storage.StorageAccount(
            f"{self._name}_storage_account",
            account_name=alphanumeric(
                f"{''.join(truncate_tokens(stack_name.split('-'), 14))}apps"
            )[:24],
            kind=storage.Kind.STORAGE_V2,
            location=props.location,
            resource_group_name=props.resource_group_name,
            sku=storage.SkuArgs(name=storage.SkuName.STANDARD_GRS),
            opts=child_opts,
            tags=child_tags,
        )

        # Create function apps container
        container = storage.BlobContainer(
            f"{self._name}_container_functions",
            account_name=storage_account.name,
            container_name="functions",
            public_access=storage.PublicAccess.NONE,
            resource_group_name=props.resource_group_name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=storage_account),
            ),
            tags=child_tags,
        )

        # Upload Gitea mirror function app
        blob_gitea_mirror = storage.Blob(
            f"{self._name}_blob_gitea_mirror",
            account_name=storage_account.name,
            container_name=container.name,
            resource_group_name=props.resource_group_name,
            source=FileArchive(
                str((resources_path / "gitea_mirror" / "functions").absolute()),
            ),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(parent=container),
            ),
            tags=child_tags,
        )

        # Deploy service plan
        app_service_plan = web.AppServicePlan(
            f"{self._name}_app_service_plan",
            kind="linux",
            location=props.location,
            name=f"{stack_name}-app-service-plan",
            resource_group_name=props.resource_group_name,
            sku={
                "name": "B1",
                "tier": "Basic",
                "size": "B1",
                "family": "B",
                "capacity": 1,
            },
        )

        # connection_string = get_connection_string()
