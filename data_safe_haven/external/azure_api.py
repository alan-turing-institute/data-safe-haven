"""Backend for a Data Safe Haven environment"""
# Standard library imports
from contextlib import suppress
import time
from typing import Any, Dict, Sequence

# Third party imports
from azure.core.exceptions import (
    HttpResponseError,
    ResourceExistsError,
    ResourceNotFoundError,
)
from azure.keyvault.certificates import (
    CertificateClient,
    CertificatePolicy,
    KeyVaultCertificate,
)
from azure.keyvault.keys import KeyClient, KeyVaultKey
from azure.keyvault.secrets import SecretClient, KeyVaultSecret
from azure.mgmt.automation import AutomationClient
from azure.mgmt.automation.models import (
    DscCompilationJobCreateParameters,
    DscConfigurationAssociationProperty,
)
from azure.mgmt.keyvault import KeyVaultManagementClient
from azure.mgmt.keyvault.models import Vault
from azure.mgmt.msi import ManagedServiceIdentityClient
from azure.mgmt.msi.models import Identity
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.resource.resources.models import ResourceGroup
from azure.mgmt.storage import StorageManagementClient
from azure.mgmt.storage.models import BlobContainer, StorageAccount

# Local imports
from .graph_api import GraphApi
from data_safe_haven.exceptions import (
    DataSafeHavenAzureException,
    DataSafeHavenInternalException,
)
from data_safe_haven.mixins import AzureMixin, LoggingMixin


class AzureApi(AzureMixin, LoggingMixin):
    """Interface to the Azure REST API"""

    def __init__(self, subscription_name: str, *args: Any, **kwargs: Any):
        super().__init__(subscription_name=subscription_name, *args, **kwargs)

    def compile_desired_state(
        self,
        automation_account_name: str,
        configuration_name: str,
        location: str,
        parameters: Dict[str, str],
        resource_group_name: str,
    ) -> None:
        """Ensure that a Powershell Desired State Configuration is compiled

        Raises:
            DataSafeHavenAzureException if the configuration could not be compiled
        """
        # Connect to Azure clients
        automation_client = AutomationClient(self.credential, self.subscription_id)
        # Begin creation
        compilation_job_name = f"{configuration_name}-{time.time_ns()}"
        with suppress(ResourceExistsError):
            automation_client.dsc_compilation_job.begin_create(
                resource_group_name=resource_group_name,
                automation_account_name=automation_account_name,
                compilation_job_name=compilation_job_name,
                parameters=DscCompilationJobCreateParameters(
                    name=compilation_job_name,
                    location=location,
                    configuration=DscConfigurationAssociationProperty(
                        name=configuration_name
                    ),
                    parameters=parameters,
                ),
            )
        # Poll until creation succeeds or fails
        while True:
            result = automation_client.dsc_compilation_job.get(
                resource_group_name=resource_group_name,
                automation_account_name=automation_account_name,
                compilation_job_name=compilation_job_name,
            )
            time.sleep(10)
            with suppress(AttributeError):
                if (result.provisioning_state == "Succeeded") and (
                    result.status == "Completed"
                ):
                    break
                if (result.provisioning_state == "Suspended") and (
                    result.status == "Suspended"
                ):
                    raise DataSafeHavenAzureException(
                        f"Could not compile DSC '{configuration_name}'\n{result.exception}."
                    )

    def ensure_azuread_application(
        self,
        aad_application_short_name: str,
        environment_name: str,
        graph_api: GraphApi,
        key_vault_name: str,
        application_scopes: Sequence[str] = [],
        delegated_scopes: Sequence[str] = [],
    ) -> str:
        """Ensure that an AzureAD application is registered

        Returns:
            str: The AzureAD application ID

        Raises:
            DataSafeHavenAzureException if the existence of the application could not be verified
        """
        try:
            aad_application_name = (
                f"sre-{environment_name}-azuread-{aad_application_short_name}"
            )
            graph_api.create_application(
                aad_application_name,
                application_scopes=application_scopes,
                delegated_scopes=delegated_scopes,
            )
            aad_application_id = graph_api.get_id_from_application_name(
                aad_application_name
            )
            self.ensure_keyvault_secret(
                key_vault_name,
                f"aad-application-id-{aad_application_name}",
                aad_application_id,
            )
            try:
                application_secret_name = (
                    f"aad-application-secret-{aad_application_name}"
                )
                application_secret = self.get_keyvault_secret(
                    key_vault_name, application_secret_name
                )
            except DataSafeHavenAzureException:
                application_secret = graph_api.create_application_secret(
                    f"SRE {environment_name} AzureAD {aad_application_short_name} secret",
                    aad_application_name,
                )
            self.ensure_keyvault_secret(
                key_vault_name, application_secret_name, application_secret
            )
            self.info(
                f"Ensured that application <fg=green>{aad_application_name}</> exists."
            )
            return aad_application_id
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Could not ensure that application '{aad_application_name}' exists.\n{str(exc)}"
            ) from exc

    def ensure_azuread_group(
        self, graph_api: GraphApi, group_name: str, group_id: str
    ) -> None:
        """Ensure that an AzureAD group is registered

        Raises:
            DataSafeHavenAzureException if the existence of the group could not be verified
        """
        try:
            self.info(
                f"Ensuring that group <fg=green>{group_name}</> exists...",
                no_newline=True,
            )
            graph_api.create_group(group_name, group_id, verbose=False)
            self.info(
                f"Ensured that group <fg=green>{group_name}</> exists.",
                overwrite=True,
            )
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Could not ensure that AzureAD group '{group_name}' exists.\n{str(exc)}"
            ) from exc

    def ensure_keyvault(
        self,
        admin_group_id: str,
        key_vault_name: str,
        location: str,
        managed_identity: Identity,
        resource_group_name: str,
        tags: Any = None,
        tenant_id: str = None,
    ) -> Vault:
        """Ensure that a KeyVault exists


        Raises:
            DataSafeHavenAzureException if the existence of the KeyVault could not be verified
        """
        try:
            self.info(
                f"Ensuring that key vault <fg=green>{key_vault_name}</> exists...",
                no_newline=True,
            )
            tenant_id = tenant_id if tenant_id else self.tenant_id

            # Connect to Azure clients
            key_vault_client = KeyVaultManagementClient(
                self.credential, self.subscription_id
            )

            # Ensure that key vault exists
            key_vault_client.vaults.begin_create_or_update(
                resource_group_name,
                key_vault_name,
                {
                    "location": location,
                    "tags": tags,
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
                                    "keys": [
                                        "GET",
                                        "LIST",
                                        "CREATE",
                                        "DECRYPT",
                                        "ENCRYPT",
                                    ],
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
            self.info(
                f"Ensured that key vault <fg=green>{key_vaults[0].name}</> exists.",
                overwrite=True,
            )
            return key_vaults[0]
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create key vault {key_vault_name}.\n{str(exc)}"
            ) from exc

    def ensure_keyvault_certificate(
        self,
        certificate_name: str,
        certificate_url: str,
        key_vault_name: str,
    ) -> KeyVaultCertificate:
        """Ensure that a self-signed certificate exists in the KeyVault

        Returns:
            str: The certificate secret ID

        Raises:
            DataSafeHavenAzureException if the existence of the certificate could not be verified
        """
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
            return certificate
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create certificate '{certificate_url}'."
            ) from exc

    def ensure_keyvault_key(
        self,
        key_name: str,
        key_vault_name: str,
    ) -> KeyVaultKey:
        """Ensure that a key exists in the KeyVault

        Returns:
            str: The key ID

        Raises:
            DataSafeHavenAzureException if the existence of the key could not be verified
        """
        try:
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
                key = key_client.get_key(key_name)
            self.info(
                f"Ensured that key <fg=green>{key_name}</> exists.",
                overwrite=True,
            )
            return key
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create key {key_name}.\n{str(exc)}"
            ) from exc

    def ensure_keyvault_secret(
        self, key_vault_name: str, secret_name: str, secret_value: str
    ) -> KeyVaultSecret:
        """Ensure that a secret exists in the KeyVault

        Returns:
            str: The secret value

        Raises:
            DataSafeHavenAzureException if the existence of the secret could not be verified
        """
        # Ensure that key exists
        self.info(
            f"Ensuring that secret <fg=green>{secret_name}</> exists...",
            no_newline=True,
        )
        try:
            try:
                secret = self.get_keyvault_secret(key_vault_name, secret_name)
            except DataSafeHavenAzureException:
                secret = None
            if not secret:
                self.set_keyvault_secret(key_vault_name, secret_name, secret_value)
                secret = self.get_keyvault_secret(key_vault_name, secret_name)
            self.info(
                f"Ensured that secret <fg=green>{secret_name}</> exists.",
                overwrite=True,
            )
            return secret
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create secret {secret_name}.\n{str(exc)}"
            ) from exc

    def ensure_managed_identity(
        self,
        identity_name: str,
        location: str,
        resource_group_name: str,
    ) -> Identity:
        """Ensure that a ManagedIdentity exists

        Returns:
            Identity: The managed identity

        Raises:
            DataSafeHavenAzureException if the existence of the managed identity could not be verified
        """
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
                f"Failed to create managed identity {identity_name}.\n{str(exc)}"
            ) from exc

    def ensure_resource_group(
        self,
        location: str,
        resource_group_name: str,
        tags: Any = None,
    ) -> ResourceGroup:
        """Ensure that a resource group exists

        Raises:
            DataSafeHavenAzureException if the existence of the resource group could not be verified
        """
        try:
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
                {"location": location, "tags": tags},
            )
            resource_groups = [
                rg
                for rg in resource_client.resource_groups.list()
                if rg.name == resource_group_name
            ]
            self.info(
                f"Ensured that resource group <fg=green>{resource_groups[0].name}</> exists in <fg=green>{resource_groups[0].location}</>.",
                overwrite=True,
            )
            return resource_groups[0]
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create resource group {resource_group_name}.\n{str(exc)}"
            ) from exc

    def ensure_storage_account(
        self,
        location: str,
        resource_group_name: str,
        storage_account_name: str,
        tags: Any = None,
    ) -> StorageAccount:
        """Ensure that a storage account exists

        Returns:
            str: The certificate secret ID

        Raises:
            DataSafeHavenAzureException if the existence of the certificate could not be verified
        """
        try:
            self.storage_account_name = storage_account_name
            # Connect to Azure clients
            storage_client = StorageManagementClient(
                self.credential, self.subscription_id
            )
            self.info(
                f"Ensuring that storage account <fg=green>{storage_account_name}</> exists...",
                no_newline=True,
            )
            poller = storage_client.storage_accounts.begin_create(
                resource_group_name,
                storage_account_name,
                {
                    "location": location,
                    "kind": "StorageV2",
                    "sku": {"name": "Standard_LRS"},
                    "tags": tags,
                },
            )
            storage_account = poller.result()
            self.info(
                f"Ensured that storage account <fg=green>{storage_account.name}</> exists.",
                overwrite=True,
            )
            return storage_account
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create storage account {storage_account_name}.\n{str(exc)}"
            ) from exc

    def ensure_storage_blob_container(
        self,
        container_name: str,
        resource_group_name: str,
        storage_account_name: str,
    ) -> BlobContainer:
        """Ensure that a storage blob container exists

        Returns:
            str: The certificate secret ID

        Raises:
            DataSafeHavenAzureException if the existence of the certificate could not be verified
        """
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
            return container
        except HttpResponseError as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create storage container <fg=green>{container_name}."
            ) from exc

    def get_keyvault_secret(
        self, key_vault_name: str, secret_name: str
    ) -> KeyVaultSecret:
        """Read a secret from the KeyVault

        Returns:
            str: The secret value

        Raises:
            DataSafeHavenAzureException if the secret could not be read
        """
        # Connect to Azure clients
        secret_client = SecretClient(
            f"https://{key_vault_name}.vault.azure.net", self.credential
        )
        # Ensure that key exists
        try:
            secret = secret_client.get_secret(secret_name)
            return secret.value
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to retrieve secret {secret_name}."
            ) from exc

    def remove_resource_group(self, resource_group_name: str) -> None:
        """Remove a resource group with its contents

        Raises:
            DataSafeHavenAzureException if the resource group could not be removed
        """
        try:
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
            if resource_groups:
                raise DataSafeHavenInternalException(
                    f"There are still {len(resource_groups)} resource group(s) remaining."
                )
            self.info(
                f"Ensured that resource group <fg=green>{resource_group_name}</> does not exist.",
                overwrite=True,
            )
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to remove resource group {resource_group_name}.\n{str(exc)}"
            ) from exc

    def set_keyvault_secret(
        self, key_vault_name: str, secret_name: str, secret_value: str
    ) -> KeyVaultSecret:
        """Ensure that a KeyVault secret has the desired value

        Returns:
            str: The secret value

        Raises:
            DataSafeHavenAzureException if the secret could not be set
        """
        try:
            # Connect to Azure clients
            secret_client = SecretClient(
                f"https://{key_vault_name}.vault.azure.net", self.credential
            )
            # Set the secret to the desired value
            secret_client.set_secret(secret_name, secret_value)
            return secret_client.get_secret(secret_name)
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to set secret '{secret_name}'.\n{str(exc)}"
            ) from exc
