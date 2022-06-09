"""Backend for a Data Safe Haven environment"""
# Standard library imports
from typing import Any, Sequence, Union

# Third party imports
from azure.core.exceptions import HttpResponseError, ResourceNotFoundError
from azure.keyvault.certificates import CertificateClient, CertificatePolicy
from azure.keyvault.keys import KeyClient
from azure.keyvault.secrets import SecretClient
from azure.mgmt.keyvault import KeyVaultManagementClient
from azure.mgmt.msi import ManagedServiceIdentityClient
from azure.mgmt.msi.models import Identity
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.storage import StorageManagementClient
from dotmap import DotMap

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.mixins import AzureMixin, LoggingMixin
from data_safe_haven.exceptions import DataSafeHavenAzureException
from data_safe_haven.helpers import GraphApi


class Backend(AzureMixin, LoggingMixin):
    """Ensure that storage backend exists"""

    def __init__(self, config: Config, *args: Any, **kwargs: Any):
        super().__init__(
            subscription_name=config.azure.subscription_name, *args, **kwargs
        )
        self.cfg = config
        self.tags = (
            {"component": "backend"} | self.cfg.tags
            if self.cfg.tags
            else {"component": "backend"}
        )
        self.certificate_id = None
        self.pulumi_encryption_key = None
        self.guacamole_application_id = None
        self.authentication_application_id = None
        self.user_management_application_id = None
        # Set any missing config values
        self.cfg.azure.subscription_id = self.get_config_value(
            self.cfg.azure.subscription_id, self.subscription_id
        )
        self.cfg.azure.tenant_id = self.get_config_value(
            self.cfg.azure.tenant_id, self.tenant_id
        )
        self.cfg.backend.identity_name = self.get_config_value(
            self.cfg.backend.identity_name, "KeyVaultReaderIdentity"
        )
        self.cfg.backend.key_vault_name = self.get_config_value(
            self.cfg.backend.key_vault_name, f"kv-{self.cfg.environment_name}-backend"
        )
        self.cfg.deployment.certificate_name = self.get_config_value(
            self.cfg.deployment.certificate_name,
            f"certificate-{self.cfg.environment_name}",
        )
        self.cfg.pulumi.encryption_key_name = self.get_config_value(
            self.cfg.pulumi.encryption_key_name,
            f"encryption-{self.cfg.environment_name}-pulumi",
        )
        self.cfg.pulumi.storage_container_name = self.get_config_value(
            self.cfg.pulumi.storage_container_name, "pulumi"
        )
        self.cfg.azure.aad_group_research_users = self.get_config_value(
            self.cfg.azure.aad_group_research_users,
            f"sre-{self.cfg.environment_name}-research-users",
        )

    def get_config_value(self, config_item: Union[str, DotMap], default_value: str):
        if isinstance(config_item, str):
            return config_item
        return default_value

    def create(self) -> None:
        resource_group_name = self.ensure_resource_group(
            location=self.cfg.azure.location,
            resource_group_name=self.cfg.backend.resource_group_name,
        )
        managed_identity = self.ensure_managed_identity(
            identity_name=self.cfg.backend.identity_name,
            location=self.cfg.azure.location,
            resource_group_name=resource_group_name,
        )
        storage_account_name = self.ensure_storage_account(
            resource_group_name=resource_group_name,
            storage_account_name=self.cfg.backend.storage_account_name,
        )
        self.ensure_storage_container(
            container_name=self.cfg.storage_container_name,
            resource_group_name=resource_group_name,
            storage_account_name=storage_account_name,
        )
        self.ensure_storage_container(
            container_name=self.cfg.pulumi.storage_container_name,
            resource_group_name=resource_group_name,
            storage_account_name=storage_account_name,
        )
        key_vault_name = self.ensure_key_vault(
            admin_group_id=self.cfg.azure.admin_group_id,
            key_vault_name=self.cfg.backend.key_vault_name,
            location=self.cfg.azure.location,
            managed_identity=managed_identity,
            resource_group_name=resource_group_name,
            tenant_id=self.cfg.azure.tenant_id,
        )
        self.pulumi_encryption_key = self.ensure_key(
            key_name=self.cfg.pulumi.encryption_key_name,
            key_vault_name=key_vault_name,
        ).replace("https:", "azurekeyvault:")
        self.certificate_id = self.ensure_cert(
            certificate_name=self.cfg.deployment.certificate_name,
            certificate_url=self.cfg.environment.url,
            key_vault_name=key_vault_name,
        )
        graph_api = GraphApi(
            tenant_id=self.cfg.azure.aad_tenant_id,
            default_scopes=["Application.ReadWrite.All", "Group.ReadWrite.All"],
        )
        self.authentication_application_id = self.ensure_azuread_application(
            application_scopes=["Group.Read.All", "User.Read.All"],
            application_short_name="authentication",
            delegated_scopes=["GroupMember.Read.All", "User.Read.All"],
            graph_api=graph_api,
            key_vault_name=key_vault_name,
        )
        self.user_management_application_id = self.ensure_azuread_application(
            application_scopes=[
                "Directory.Read.All",
                "Domain.Read.All",
                "Group.ReadWrite.All",
                "User.ReadWrite.All",
                "UserAuthenticationMethod.ReadWrite.All",
            ],
            application_short_name="user-management",
            graph_api=graph_api,
            key_vault_name=key_vault_name,
        )
        # Register Guacamole application as an OpenID redirect endpoint
        application_name = f"sre-{self.cfg.environment_name}-azuread-guacamole"
        guacamole_app = graph_api.application(
            application_name=application_name,
            request_json={
                "displayName": application_name,
                "web": {
                    "redirectUris": [f"https://{self.cfg.environment.url}"],
                    "implicitGrantSettings": {"enableIdTokenIssuance": True},
                },
                "signInAudience": "AzureADMyOrg",
            },
        )
        self.guacamole_application_id = guacamole_app["appId"]
        self.ensure_azuread_group(
            graph_api, self.cfg.azure.aad_group_research_users, 20000
        )

    def destroy(self) -> None:
        self.remove_resource_group(self.cfg.backend.resource_group_name)

    def ensure_azuread_application(
        self,
        application_short_name: str,
        graph_api: GraphApi,
        key_vault_name: str,
        application_scopes: Sequence[str] = [],
        delegated_scopes: Sequence[str] = [],
    ) -> None:
        """Ensure that an AzureAD application is registered"""
        application_name = (
            f"sre-{self.cfg.environment_name}-azuread-{application_short_name}"
        )
        aad_application = graph_api.application(
            application_name=application_name,
            application_scopes=application_scopes,
            delegated_scopes=delegated_scopes,
        )
        self.ensure_secret(
            key_vault_name,
            f"azuread-{application_short_name}-application-id",
            aad_application["appId"],
        )
        try:
            application_secret_name = (
                f"azuread-{application_short_name}-application-secret"
            )
            application_secret = self.get_secret(
                key_vault_name, application_secret_name
            )
        except DataSafeHavenAzureException:
            application_secret = graph_api.application_secret(
                f"SRE {self.cfg.environment_name} AzureAD {application_short_name} secret",
                aad_application,
            )
        self.ensure_secret(key_vault_name, application_secret_name, application_secret)
        self.info(f"Ensured that application <fg=green>{application_name}</> exists.")
        return aad_application["appId"]

    def ensure_azuread_group(self, graph_api, group_name, group_id):
        """Ensure that an AzureAD group exists"""
        self.info(
            f"Ensuring that group <fg=green>{group_name}</> exists...",
            no_newline=True,
        )
        group = graph_api.create_group(group_name, group_id)
        self.info(
            f"Ensured that group <fg=green>{group_name}</> exists.",
            overwrite=True,
        )
        return group

    def ensure_cert(
        self,
        certificate_name: str,
        certificate_url: str,
        key_vault_name: str,
    ) -> str:
        """Ensure that self-signed certificate exists"""
        try:
            # Connect to Azure clients
            certificate_client = CertificateClient(
                vault_url=f"https://{key_vault_name}.vault.azure.net",
                credential=self.credential,
            )

            # Ensure that certificate exists
            self.info(
                f"Ensuring that certificate <fg=green>{certificate_url}</> exists...",
                no_newline=True,
            )
            policy = CertificatePolicy(
                issuer_name="Self",
                subject=f"CN={certificate_url}",
                exportable=True,
                key_type="RSA",
                key_size=2048,
                reuse_key=False,
                enhanced_key_usage=["1.3.6.1.5.5.7.3.1", "1.3.6.1.5.5.7.3.2"],
                validity_in_months=12,
            )
            poller = certificate_client.begin_create_certificate(
                certificate_name=certificate_name, policy=policy
            )
            certificate = poller.result()
            self.info(
                f"Ensured that certificate <fg=green>{certificate_url}</> exists.",
                overwrite=True,
            )
            return certificate.secret_id
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create certificate <fg=green>{certificate_url}</>."
            ) from exc

    def ensure_key(
        self,
        key_name: str,
        key_vault_name: str,
    ) -> str:
        """Ensure that a key exists in the keyvault"""
        # Connect to Azure clients
        key_client = KeyClient(
            f"https://{key_vault_name}.vault.azure.net", self.credential
        )

        # Ensure that key exists
        self.info(
            f"Ensuring that key <fg=green>{key_name}</> exists...",
            no_newline=True,
        )
        key = None
        try:
            key = key_client.get_key(key_name)
        except (HttpResponseError, ResourceNotFoundError):
            key_client.create_rsa_key(key_name, size=2048)
        try:
            if not key:
                key = key_client.get_key(key_name)
            self.info(
                f"Ensured that key <fg=green>{key_name}</> exists.",
                overwrite=True,
            )
            return key.id
        except (HttpResponseError, ResourceNotFoundError):
            raise DataSafeHavenAzureException(f"Failed to create key {key_name}.")

    def ensure_key_vault(
        self,
        admin_group_id: str,
        key_vault_name: str,
        location: str,
        managed_identity: Identity,
        resource_group_name: str,
        tenant_id: str,
    ) -> str:
        """Ensure that backend key vault exists"""
        # Connect to Azure clients
        key_vault_client = KeyVaultManagementClient(
            self.credential, self.subscription_id
        )

        # Ensure that key vault exists
        self.info(
            f"Ensuring that key vault <fg=green>{key_vault_name}</> exists...",
            no_newline=True,
        )
        key_vault_client.vaults.begin_create_or_update(
            resource_group_name,
            key_vault_name,
            {
                "location": location,
                "tags": self.tags,
                "properties": {
                    "sku": {
                        "name": "standard",
                        "family": "A",
                    },
                    "tenant_id": tenant_id,
                    "access_policies": [
                        {
                            "tenant_id": tenant_id,
                            "object_id": admin_group_id,
                            "permissions": {
                                "keys": ["GET", "LIST", "CREATE", "DECRYPT", "ENCRYPT"],
                                "secrets": ["GET", "LIST", "SET"],
                                "certificates": ["GET", "LIST", "CREATE"],
                            },
                        },
                        {
                            "tenant_id": self.tenant_id,
                            "object_id": managed_identity.principal_id,
                            "permissions": {
                                "secrets": ["GET", "LIST"],
                                "certificates": ["GET", "LIST"],
                            },
                        },
                    ],
                },
            },
        )
        key_vaults = [
            kv for kv in key_vault_client.vaults.list() if kv.name == key_vault_name
        ]
        if key_vaults:
            self.info(
                f"Ensured that key vault <fg=green>{key_vaults[0].name}</> exists.",
                overwrite=True,
            )
            return key_vaults[0].name
        else:
            raise DataSafeHavenAzureException(
                f"Failed to create key vault {key_vault_name}."
            )

    def ensure_managed_identity(
        self,
        identity_name: str,
        location: str,
        resource_group_name: str,
    ) -> Identity:
        """Ensure that managed identity exists"""
        try:
            self.info(
                f"Ensuring that managed identity <fg=green>{identity_name}</> exists...",
                no_newline=True,
            )
            msi_client = ManagedServiceIdentityClient(
                self.credential, self.subscription_id
            )
            managed_identity = msi_client.user_assigned_identities.create_or_update(
                resource_group_name,
                identity_name,
                {"location": location},
            )
            self.info(
                f"Ensured that managed identity <fg=green>{identity_name}</> exists.",
                overwrite=True,
            )
            return managed_identity
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create managed identity {identity_name}."
            ) from exc

    def ensure_resource_group(
        self,
        location: str,
        resource_group_name: str,
    ) -> str:
        """Ensure that backend resource group exists"""
        # Connect to Azure clients
        resource_client = ResourceManagementClient(
            self.credential, self.subscription_id
        )

        # Ensure that resource group exists
        self.info(
            f"Ensuring that resource group <fg=green>{resource_group_name}</> exists...",
            no_newline=True,
        )
        resource_client.resource_groups.create_or_update(
            resource_group_name,
            {"location": location, "tags": self.tags},
        )
        resource_groups = [
            rg
            for rg in resource_client.resource_groups.list()
            if rg.name == resource_group_name
        ]
        if resource_groups:
            self.info(
                f"Ensured that resource group <fg=green>{resource_groups[0].name}</> exists in <fg=green>{resource_groups[0].location}</>.",
                overwrite=True,
            )
            return resource_groups[0].name
        else:
            raise DataSafeHavenAzureException(
                f"Failed to create resource group {resource_group_name}."
            )

    def ensure_secret(
        self, key_vault_name: str, secret_name: str, secret_value: str
    ) -> str:
        """Ensure that a secret exists in the keyvault"""
        # Ensure that key exists
        self.info(
            f"Ensuring that secret <fg=green>{secret_name}</> exists...",
            no_newline=True,
        )
        try:
            secret = self.get_secret(key_vault_name, secret_name)
        except DataSafeHavenAzureException:
            secret = None
        try:
            if not secret:
                self.set_secret(key_vault_name, secret_name, secret_value)
                secret = self.get_secret(key_vault_name, secret_name)
            self.info(
                f"Ensured that secret <fg=green>{secret_name}</> exists.",
                overwrite=True,
            )
            return secret
        except DataSafeHavenAzureException:
            raise DataSafeHavenAzureException(f"Failed to create secret {secret_name}.")

    def ensure_storage_account(
        self, resource_group_name: str, storage_account_name: str
    ) -> str:
        """Ensure that backend storage account exists"""
        self.storage_account_name = storage_account_name
        # Connect to Azure clients
        storage_client = StorageManagementClient(self.credential, self.subscription_id)

        self.info(
            f"Ensuring that storage account <fg=green>{storage_account_name}</> exists...",
            no_newline=True,
        )
        try:
            poller = storage_client.storage_accounts.begin_create(
                resource_group_name,
                storage_account_name,
                {
                    "location": self.cfg.azure.location,
                    "kind": "StorageV2",
                    "sku": {"name": "Standard_LRS"},
                    "tags": self.tags,
                },
            )
            storage_account = poller.result()
            self.info(
                f"Ensured that storage account <fg=green>{storage_account.name}</> exists.",
                overwrite=True,
            )
            return storage_account.name
        except HttpResponseError as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create storage account {storage_account_name}."
            ) from exc

    def ensure_storage_container(
        self,
        container_name: str,
        resource_group_name: str,
        storage_account_name: str,
    ) -> str:
        """Ensure that backend storage container exists"""
        # Connect to Azure clients
        storage_client = StorageManagementClient(self.credential, self.subscription_id)

        self.info(
            f"Ensuring that storage container <fg=green>{container_name}</> exists...",
            no_newline=True,
        )
        try:
            container = storage_client.blob_containers.create(
                resource_group_name,
                storage_account_name,
                container_name,
                {"public_access": "none"},
            )
            self.info(
                f"Ensured that storage container <fg=green>{container.name}</> exists.",
                overwrite=True,
            )
            return container.name
        except HttpResponseError as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create storage container <fg=green>{container_name}."
            ) from exc

    def get_secret(self, key_vault_name: str, secret_name: str) -> str:
        """Read a secret from the keyvault"""
        # Connect to Azure clients
        secret_client = SecretClient(
            f"https://{key_vault_name}.vault.azure.net", self.credential
        )
        # Ensure that key exists
        try:
            secret = secret_client.get_secret(secret_name)
            return secret.value
        except (HttpResponseError, ResourceNotFoundError):
            raise DataSafeHavenAzureException(
                f"Failed to retrieve secret {secret_name}."
            )

    def remove_resource_group(self, resource_group_name: str) -> None:
        """Ensure that backend resource group exists"""
        # Connect to Azure clients
        resource_client = ResourceManagementClient(
            self.credential, self.subscription_id
        )

        # Ensure that resource group exists
        self.info(
            f"Removing resource group <fg=green>{resource_group_name}</> if it exists...",
            no_newline=True,
        )
        poller = resource_client.resource_groups.begin_delete(
            resource_group_name,
        )
        while not poller.done():
            poller.wait(10)
        resource_groups = [
            rg
            for rg in resource_client.resource_groups.list()
            if rg.name == resource_group_name
        ]
        if not resource_groups:
            self.info(
                f"Ensured that resource group <fg=green>{resource_group_name}</> does not exist.",
                overwrite=True,
            )
        else:
            raise DataSafeHavenAzureException(
                f"Failed to remove resource group {resource_group_name}."
            )

    def set_secret(
        self, key_vault_name: str, secret_name: str, secret_value: str
    ) -> str:
        """Set a secret in the keyvault to a desired value"""
        # Connect to Azure clients
        secret_client = SecretClient(
            f"https://{key_vault_name}.vault.azure.net", self.credential
        )
        # Set the secret to the desired value
        secret_client.set_secret(secret_name, secret_value)
        try:
            return secret_client.get_secret(secret_name)
        except (HttpResponseError, ResourceNotFoundError):
            raise DataSafeHavenAzureException(f"Failed to create secret {secret_name}.")

    def update_config(self) -> None:
        """Add backend settings to config"""
        self.cfg.deployment.certificate_id = self.certificate_id
        self.cfg.deployment.aad_app_id_guacamole = self.guacamole_application_id
        self.cfg.deployment.aad_app_id_authentication = (
            self.authentication_application_id
        )
        self.cfg.deployment.aad_app_id_user_management = (
            self.user_management_application_id
        )
        self.cfg.pulumi.encryption_key = self.pulumi_encryption_key
