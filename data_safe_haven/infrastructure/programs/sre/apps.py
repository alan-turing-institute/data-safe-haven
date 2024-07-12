"""Pulumi component for SRE function/web apps"""

from typing import Mapping

from pulumi import ComponentResource, ResourceOptions, Input, FileArchive
from pulumi_azure_native import (
    resources,
    storage,
    web,
)

from data_safe_haven.functions import (
    alphanumeric,
    truncate_tokens,
)
from data_safe_haven.resources import resources_path


class SREAppsProps:
    """Properties for SREAppsComponent"""
    pass


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

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-apps",
            opts=child_opts,
            tags=child_tags,
        )

        # Deploy storage account
        # The storage account holds app data/configuration
        storage_account = storage.StorageAccount(
            f"{self._name}_storage_account",
            account_name=alphanumeric(
                f"{''.join(truncate_tokens(stack_name.split('-'), 14))}apps"
            )[:24],
            kind=storage.Kind.STORAGE_V2,
            location=props.location,
            resource_group_name=resource_group.name,
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
            resource_group_name=resource_group.name,
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
            resource_group_name=resource_group.name,
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
            resource_group_name=resource_group.name,
            sku={
                "name": "B1",
                "tier": "Basic",
                "size": "B1",
                "family": "B",
                "capacity": 1
            }
        )

        # connection_string = get_connection_string()
