"""Pulumi component for SRE function/web apps"""

from collections.abc import Mapping

from pulumi import ComponentResource, FileArchive, Input, Output, ResourceOptions
from pulumi_azure_native import (
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

    def __init__(
        self,
        location: Input[str],
        resource_group_name: Input[str],
    ):
        self.location = location
        self.resource_group_name = resource_group_name


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
        )

        # Get URL of app blob
        blob_url = get_blob_url(
            blob=blob_gitea_mirror,
            container=container,
            storage_account=storage_account,
            resource_group_name=props.resource_group_name,
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
            tags=child_tags,
        )

        # Deploy app
        web.WebApp(
            f"{self._name}_web_app",
            enabled=True,
            https_only=True,
            kind="FunctionApp",
            location=props.location,
            name="giteamirror",
            resource_group_name=props.resource_group_name,
            server_farm_id=app_service_plan.id,
            site_config=web.SiteConfig(
                app_settings=[
                    {"name": "runtime", "value": "python"},
                    {"name": "FUNCTIONS_WORKER_RUNTIME", "value": "python"},
                    {"name": "WEBSITE_RUN_FROM_PACKAGE", "value": blob_url},
                    {"name": "FUNCTIONS_EXTENSION_VERSION", "value": "~4"},
                ],
            ),
            tags=child_tags,
        )


def get_blob_url(
    blob: Input[storage.Blob],
    container: Input[storage.BlobContainer],
    storage_account: Input[storage.StorageAccount],
    resource_group_name: Input[str],
) -> Output[str]:
    sas = storage.list_storage_account_service_sas_output(
        account_name=storage_account.name,
        protocols=storage.HttpProtocol.HTTPS,
        # shared_access_expiry_time="2030-01-01",
        # shared_access_start_time="2021-01-01",
        resource_group_name=resource_group_name,
        # Access to container
        resource=storage.SignedResource.C,
        # Read access
        permissions=storage.Permissions.R,
        canonicalized_resource=Output.format(
            "/blob/{account_name}/{container_name}",
            account_name=storage_account.name,
            container_name=container.name,
        ),
        content_type="application/json",
        cache_control="max-age=5",
        content_disposition="inline",
        content_encoding="deflate",
    )
    token = sas.service_sas_token
    # return Output.format(
    #     "https://{0}.blob.core.windows.net/{1}/{2}?{3}",
    #     storage_account.name,
    #     container.name,
    #     blob.name,
    #     token,
    # )
    return Output.format(
        "https://{storage_account_name}.blob.core.windows.net/{container_name}/{blob_name}?{token}",
        storage_account_name=storage_account.name,
        container_name=container.name,
        blob_name=blob.name,
        token=token,
    )
