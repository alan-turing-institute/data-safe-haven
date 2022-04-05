"""Backend for a Data Safe Haven environment"""
# Third party imports
from azure.core.exceptions import HttpResponseError, ResourceNotFoundError
from azure.keyvault.certificates import CertificateClient, CertificatePolicy
from azure.keyvault.keys import KeyClient
from azure.mgmt.keyvault import KeyVaultManagementClient
from azure.mgmt.msi import ManagedServiceIdentityClient
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.storage import StorageManagementClient

# Local imports
from data_safe_haven.mixins import AzureMixin, LoggingMixin
from data_safe_haven.exceptions import DataSafeHavenAzureException


class Backend(AzureMixin, LoggingMixin):
    """Ensure that storage backend exists"""

    def __init__(self, config, *args, **kwargs):
        super().__init__(
            subscription_name=config.azure.subscription_name, *args, **kwargs
        )
        self.cfg = config
        self.tags = (
            {"component": "backend"} | self.cfg.tags
            if self.cfg.tags
            else {"component": "backend"}
        )
        self.resource_group_name = None
        self.managed_identity = None
        self.storage_account_name = None
        self.key_vault_name = None
        self.cfg.azure.subscription_id = self.subscription_id
        self.cfg.azure.tenant_id = self.tenant_id
        self.cfg.backend.identity_name = "KeyVaultReaderIdentity"
        self.cfg.backend.key_vault_name = f"kv-{self.cfg.environment_name}-backend"
        self.cfg.deployment.certificate_name = (
            f"certificate-{self.cfg.environment_name}"
        )
        self.cfg.pulumi.encryption_key_name = (
            f"encryption-{self.cfg.environment_name}-pulumi"
        )
        self.cfg.pulumi.storage_container_name = "pulumi"

    def create(self):
        self.ensure_resource_group(self.cfg.backend.resource_group_name)
        self.ensure_managed_identity(self.cfg.backend.identity_name)
        self.ensure_storage_account(self.cfg.backend.storage_account_name)
        self.ensure_storage_container(self.cfg.storage_container_name)
        self.ensure_storage_container(self.cfg.pulumi.storage_container_name)
        self.ensure_key_vault(self.cfg.backend.key_vault_name)
        self.ensure_key(self.cfg.pulumi.encryption_key_name)
        self.ensure_cert(self.cfg.deployment.certificate_name, self.cfg.environment.url)

    def ensure_cert(self, certificate_name, certificate_url):
        """Ensure that self-signed certificate exists"""
        try:
            # Connect to Azure clients
            certificate_client = CertificateClient(
                vault_url=f"https://{self.key_vault_name}.vault.azure.net",
                credential=self.credential,
            )

            # Ensure that certificate exists
            self.info(
                f"Ensuring that certificate for <fg=green>{certificate_url}</> exists...",
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
            self.cfg.deployment.certificate_id = certificate.secret_id
            self.info(
                f"Ensured that certificate for <fg=green>{certificate_url}</> exists.",
                overwrite=True,
            )
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create certificate {certificate_name}."
            ) from exc

    def ensure_key(self, key_name):
        """Ensure that a key exists in the keyvault"""
        # Connect to Azure clients
        key_client = KeyClient(
            f"https://{self.key_vault_name}.vault.azure.net", self.credential
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
            self.cfg.pulumi.encryption_key = key.id.replace("https:", "azurekeyvault:")
        except (HttpResponseError, ResourceNotFoundError):
            raise DataSafeHavenAzureException(f"Failed to create key {key_name}.")

    def ensure_key_vault(self, key_vault_name):
        """Ensure that backend key vault exists"""
        self.key_vault_name = key_vault_name
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
            self.resource_group_name,
            key_vault_name,
            {
                "location": self.cfg.azure.location,
                "tags": self.tags,
                "properties": {
                    "sku": {
                        "name": "standard",
                        "family": "A",
                    },
                    "tenant_id": self.tenant_id,
                    "access_policies": [
                        {
                            "tenant_id": self.tenant_id,
                            "object_id": self.cfg.azure.admin_group_id,
                            "permissions": {
                                "keys": ["GET", "LIST", "CREATE", "DECRYPT", "ENCRYPT"],
                                "secrets": ["GET", "LIST", "SET"],
                                "certificates": ["GET", "LIST", "CREATE"],
                            },
                        },
                        {
                            "tenant_id": self.tenant_id,
                            "object_id": self.managed_identity.principal_id,
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
                f"Ensured that key vault <fg=green>{key_vault_name}</> exists.",
                overwrite=True,
            )
        else:
            raise DataSafeHavenAzureException(
                f"Failed to create key vault {key_vault_name}."
            )

    def ensure_managed_identity(self, identity_name):
        """Ensure that managed identity exists"""
        try:
            self.info(
                f"Ensuring that managed identity <fg=green>{identity_name}</> exists...",
                no_newline=True,
            )
            msi_client = ManagedServiceIdentityClient(
                self.credential, self.subscription_id
            )
            self.managed_identity = (
                msi_client.user_assigned_identities.create_or_update(
                    self.cfg.backend.resource_group_name,
                    identity_name,
                    {"location": self.cfg.azure.location},
                )
            )
            self.info(
                f"Ensured that managed identity <fg=green>{identity_name}</> exists.",
                overwrite=True,
            )
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create managed identity {identity_name}."
            ) from exc

    def ensure_resource_group(self, resource_group_name):
        """Ensure that backend resource group exists"""
        self.resource_group_name = self.cfg.backend.resource_group_name
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
            {"location": self.cfg.azure.location, "tags": self.tags},
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
        else:
            raise DataSafeHavenAzureException(
                f"Failed to create resource group {resource_group_name}."
            )

    def ensure_storage_account(self, storage_account_name):
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
                self.resource_group_name,
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
        except HttpResponseError as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create storage account {storage_account_name}."
            ) from exc

    def ensure_storage_container(self, container_name):
        """Ensure that backend storage container exists"""
        # Connect to Azure clients
        storage_client = StorageManagementClient(self.credential, self.subscription_id)

        self.info(
            f"Ensuring that storage container <fg=green>{container_name}</> exists...",
            no_newline=True,
        )
        try:
            container = storage_client.blob_containers.create(
                self.resource_group_name,
                self.storage_account_name,
                container_name,
                {"public_access": "none"},
            )
            self.info(
                f"Ensured that storage container <fg=green>{container.name}</> exists.",
                overwrite=True,
            )
        except HttpResponseError as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create storage container <fg=green>{container_name}."
            ) from exc
