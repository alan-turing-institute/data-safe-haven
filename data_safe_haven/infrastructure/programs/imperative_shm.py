from data_safe_haven.config import Context, SHMConfig
from data_safe_haven.exceptions import (
    DataSafeHavenAzureError,
    DataSafeHavenMicrosoftGraphError,
)
from data_safe_haven.external import AzureSdk, GraphApi
from data_safe_haven.logging import get_logger


class ImperativeSHM:
    """Azure resources to support Data Safe Haven context"""

    def __init__(self, context: Context, config: SHMConfig) -> None:
        self.azure_sdk_: AzureSdk | None = None
        self.config = config
        self.context = context
        self.tags = {"component": "SHM", "deployed with": "Python"} | context.tags

    @property
    def azure_sdk(self) -> AzureSdk:
        """Load AzureAPI on demand

        Returns:
            AzureSdk: An initialised AzureSdk object
        """
        if not self.azure_sdk_:
            self.azure_sdk_ = AzureSdk(
                subscription_name=self.context.subscription_name,
            )
        return self.azure_sdk_

    def deploy(self) -> None:
        """Deploy all desired resources

        Raises:
            DataSafeHavenAzureError if any resources cannot be created
        """
        logger = get_logger()
        logger.info(f"Preparing to deploy [green]{self.context.description}[/] SHM.")
        # Deploy the resources needed by Pulumi
        try:
            resource_group = self.azure_sdk.ensure_resource_group(
                location=self.config.azure.location,
                resource_group_name=self.context.resource_group_name,
                tags=self.tags,
            )
            if not resource_group.name:
                msg = f"Resource group '{self.context.resource_group_name}' was not created."
                raise DataSafeHavenAzureError(msg)
            identity = self.azure_sdk.ensure_managed_identity(
                identity_name=self.context.managed_identity_name,
                location=resource_group.location,
                resource_group_name=resource_group.name,
            )
            storage_account = self.azure_sdk.ensure_storage_account(
                location=resource_group.location,
                resource_group_name=resource_group.name,
                storage_account_name=self.context.storage_account_name,
                tags=self.tags,
            )
            if not storage_account.name:
                msg = f"Storage account '{self.context.storage_account_name}' was not created."
                raise DataSafeHavenAzureError(msg)
            _ = self.azure_sdk.ensure_storage_blob_container(
                container_name=self.context.storage_container_name,
                resource_group_name=resource_group.name,
                storage_account_name=storage_account.name,
            )
            _ = self.azure_sdk.ensure_storage_blob_container(
                container_name=self.context.pulumi_storage_container_name,
                resource_group_name=resource_group.name,
                storage_account_name=storage_account.name,
            )
            keyvault = self.azure_sdk.ensure_keyvault(
                admin_group_id=self.config.shm.admin_group_id,
                key_vault_name=self.context.key_vault_name,
                location=resource_group.location,
                managed_identity=identity,
                resource_group_name=resource_group.name,
                tags=self.tags,
            )
            if not keyvault.name:
                msg = f"Keyvault '{self.context.key_vault_name}' was not created."
                raise DataSafeHavenAzureError(msg)
            self.azure_sdk.ensure_keyvault_key(
                key_name=self.context.pulumi_encryption_key_name,
                key_vault_name=keyvault.name,
            )
        except DataSafeHavenAzureError as exc:
            msg = "Failed to deploy resources needed by Pulumi."
            raise DataSafeHavenAzureError(msg) from exc

        # Deploy common resources that will be needed by SREs
        try:
            zone = self.azure_sdk.ensure_dns_zone(
                resource_group_name=resource_group.name,
                zone_name=self.config.shm.fqdn,
                tags=self.tags,
            )
            if not zone.name_servers:
                msg = f"DNS zone '{self.config.shm.fqdn}' was not created."
                raise DataSafeHavenAzureError(msg)
            nameservers = [str(n) for n in zone.name_servers]
            self.azure_sdk.ensure_dns_caa_record(
                record_flags=0,
                record_name="@",
                record_tag="issue",
                record_value="letsencrypt.org",
                resource_group_name=resource_group.name,
                ttl=3600,
                zone_name=self.config.shm.fqdn,
            )
        except DataSafeHavenAzureError as exc:
            msg = "Failed to create SHM resources."
            raise DataSafeHavenAzureError(msg) from exc

        # Connect to GraphAPI
        graph_api = GraphApi.from_scopes(
            scopes=[
                "Application.ReadWrite.All",
                "Domain.ReadWrite.All",
                "Group.ReadWrite.All",
            ],
            tenant_id=self.config.shm.entra_tenant_id,
        )
        # Add the SHM domain to the Entra ID via interactive GraphAPI
        try:
            # Generate the verification record
            verification_record = graph_api.add_custom_domain(self.config.shm.fqdn)
            # Add the record to DNS
            self.azure_sdk.ensure_dns_txt_record(
                record_name="@",
                record_value=verification_record,
                resource_group_name=resource_group.name,
                ttl=3600,
                zone_name=self.config.shm.fqdn,
            )
            # Verify the record
            graph_api.verify_custom_domain(
                self.config.shm.fqdn,
                nameservers,
            )
        except (DataSafeHavenMicrosoftGraphError, DataSafeHavenAzureError) as exc:
            msg = f"Failed to add custom domain '{self.config.shm.fqdn}' to Entra ID."
            raise DataSafeHavenAzureError(msg) from exc
        # Create an application for use by the pulumi-azuread module
        try:
            graph_api.create_application(
                self.context.entra_application_name,
                application_scopes=["Group.ReadWrite.All"],
                delegated_scopes=[],
                request_json={
                    "displayName": self.context.entra_application_name,
                    "signInAudience": "AzureADMyOrg",
                },
            )
            # Ensure that the application secret exists
            if not self.context.entra_application_secret:
                self.context.entra_application_secret = (
                    graph_api.create_application_secret(
                        self.context.entra_application_name,
                        self.context.entra_application_secret_name,
                    )
                )
        except DataSafeHavenMicrosoftGraphError as exc:
            msg = "Failed to create deployment application in Entra ID."
            raise DataSafeHavenAzureError(msg) from exc

    def teardown(self) -> None:
        """Destroy all created resources

        Raises:
            DataSafeHavenAzureError if any resources cannot be destroyed
        """
        logger = get_logger()
        try:
            logger.info(
                f"Removing [green]{self.context.description}[/] resource group {self.context.resource_group_name}."
            )
            self.azure_sdk.remove_resource_group(self.context.resource_group_name)
        except DataSafeHavenAzureError as exc:
            msg = "Failed to destroy context resources."
            raise DataSafeHavenAzureError(msg) from exc
