"""Interface to the Azure Python SDK"""
import time
from collections.abc import Sequence
from contextlib import suppress
from typing import Any, cast

from azure.core.exceptions import (
    HttpResponseError,
    ResourceExistsError,
    ResourceNotFoundError,
)
from azure.core.polling import LROPoller
from azure.keyvault.certificates import (
    CertificateClient,
    CertificatePolicy,
    KeyVaultCertificate,
)
from azure.keyvault.keys import KeyClient, KeyVaultKey
from azure.keyvault.secrets import KeyVaultSecret, SecretClient
from azure.mgmt.automation import AutomationClient
from azure.mgmt.automation.models import (
    DscCompilationJobCreateParameters,
    DscConfigurationAssociationProperty,
    Module,
)
from azure.mgmt.compute.v2021_07_01 import ComputeManagementClient
from azure.mgmt.compute.v2021_07_01.models import (
    ResourceSkuCapabilities,
    RunCommandInput,
    RunCommandInputParameter,
    RunCommandResult,
)
from azure.mgmt.dns.v2018_05_01 import DnsManagementClient
from azure.mgmt.dns.v2018_05_01.models import RecordSet, TxtRecord
from azure.mgmt.keyvault.v2021_06_01_preview import KeyVaultManagementClient
from azure.mgmt.keyvault.v2021_06_01_preview.models import (
    AccessPolicyEntry,
    Permissions,
    Sku as KeyVaultSku,
    Vault,
    VaultCreateOrUpdateParameters,
    VaultProperties,
)
from azure.mgmt.msi.v2022_01_31_preview import ManagedServiceIdentityClient
from azure.mgmt.msi.v2022_01_31_preview.models import Identity
from azure.mgmt.resource.resources.v2021_04_01 import ResourceManagementClient
from azure.mgmt.resource.resources.v2021_04_01.models import ResourceGroup
from azure.mgmt.resource.subscriptions import SubscriptionClient
from azure.mgmt.resource.subscriptions.models import Location
from azure.mgmt.storage.v2021_08_01 import StorageManagementClient
from azure.mgmt.storage.v2021_08_01.models import (
    BlobContainer,
    Kind as StorageAccountKind,
    PublicAccess,
    Sku as StorageAccountSku,
    StorageAccount,
    StorageAccountCreateParameters,
    StorageAccountKey,
    StorageAccountListKeysResult,
)
from azure.storage.blob import BlobServiceClient
from azure.storage.filedatalake import DataLakeServiceClient

from data_safe_haven.exceptions import (
    DataSafeHavenAzureError,
    DataSafeHavenInternalError,
)
from data_safe_haven.external.interface.azure_authenticator import AzureAuthenticator
from data_safe_haven.utility import LoggingSingleton


class AzureApi(AzureAuthenticator):
    """Interface to the Azure REST API"""

    def __init__(self, subscription_name: str):
        super().__init__(subscription_name)
        self.logger = LoggingSingleton()

    def compile_desired_state(
        self,
        automation_account_name: str,
        configuration_name: str,
        location: str,
        parameters: dict[str, str],
        resource_group_name: str,
        required_modules: Sequence[str],
    ) -> None:
        """Ensure that a Powershell Desired State Configuration is compiled

        Raises:
            DataSafeHavenAzureError if the configuration could not be compiled
        """
        # Connect to Azure clients
        automation_client = AutomationClient(self.credential, self.subscription_id)
        # Wait until all modules are available
        while True:
            # Cast to correct spurious type hint in Azure libraries
            available_modules = cast(
                list[Module],
                automation_client.module.list_by_automation_account(
                    resource_group_name, automation_account_name
                ),
            )
            available_module_names = [
                module.name
                for module in available_modules
                if module.provisioning_state == "Succeeded"
            ]
            if all(
                module_name in available_module_names
                for module_name in required_modules
            ):
                break
            time.sleep(10)
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
                    msg = f"Could not compile DSC '{configuration_name}'\n{result.exception}."
                    raise DataSafeHavenAzureError(msg)

    def download_blob(
        self,
        blob_name: str,
        resource_group_name: str,
        storage_account_name: str,
        storage_container_name: str,
    ) -> str:
        """Download a blob file from Azure storage

        Returns:
            str: The contents of the blob

        Raises:
            DataSafeHavenAzureError if the blob could not be downloaded
        """
        try:
            # Connect to Azure client
            storage_account_keys = self.get_storage_account_keys(
                resource_group_name, storage_account_name
            )
            blob_service_client = BlobServiceClient.from_connection_string(
                f"DefaultEndpointsProtocol=https;AccountName={storage_account_name};AccountKey={storage_account_keys[0].value};EndpointSuffix=core.windows.net"
            )
            if not isinstance(blob_service_client, BlobServiceClient):
                msg = f"Could not connect to storage account '{storage_account_name}'."
                raise DataSafeHavenAzureError(msg)
            # Download the requested file
            blob_client = blob_service_client.get_blob_client(
                container=storage_container_name, blob=blob_name
            )
            return str(blob_client.download_blob(encoding="utf-8").readall())
        except Exception as exc:
            msg = f"Blob file '{blob_name}' could not be downloaded from '{storage_account_name}'\n{exc}."
            raise DataSafeHavenAzureError(msg) from exc

    def ensure_dns_txt_record(
        self,
        record_name: str,
        record_value: str,
        resource_group_name: str,
        zone_name: str,
    ) -> RecordSet:
        """Ensure that a DNS record exists in a DNS zone

        Returns:
            RecordSet: The DNS record set

        Raises:
            DataSafeHavenAzureError if the record could not be created
        """
        try:
            # Connect to Azure clients
            dns_client = DnsManagementClient(self.credential, self.subscription_id)

            # Ensure that record exists
            self.logger.debug(
                f"Ensuring that DNS record {record_name} exists in zone {zone_name}...",
            )
            record_set = dns_client.record_sets.create_or_update(
                parameters=RecordSet(
                    ttl=30, txt_records=[TxtRecord(value=[record_value])]
                ),
                record_type="TXT",
                relative_record_set_name=record_name,
                resource_group_name=resource_group_name,
                zone_name=zone_name,
            )
            self.logger.info(
                f"Ensured that DNS record {record_name} exists in zone {zone_name}.",
            )
            return record_set
        except Exception as exc:
            msg = (
                f"Failed to create DNS record {record_name} in zone {zone_name}.\n{exc}"
            )
            raise DataSafeHavenAzureError(msg) from exc

    def ensure_keyvault(
        self,
        admin_group_id: str,
        key_vault_name: str,
        location: str,
        managed_identity: Identity,
        resource_group_name: str,
        tags: Any = None,
        tenant_id: str | None = None,
    ) -> Vault:
        """Ensure that a KeyVault exists

        Raises:
            DataSafeHavenAzureError if the existence of the KeyVault could not be verified
        """
        try:
            self.logger.debug(
                f"Ensuring that key vault [green]{key_vault_name}[/] exists...",
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
                VaultCreateOrUpdateParameters(
                    location=location,
                    tags=tags,
                    properties=VaultProperties(
                        tenant_id=tenant_id,
                        sku=KeyVaultSku(name="standard", family="A"),
                        access_policies=[
                            AccessPolicyEntry(
                                tenant_id=tenant_id,
                                object_id=admin_group_id,
                                permissions=Permissions(
                                    keys=[
                                        "GET",
                                        "LIST",
                                        "CREATE",
                                        "DECRYPT",
                                        "ENCRYPT",
                                    ],
                                    secrets=["GET", "LIST", "SET"],
                                    certificates=["GET", "LIST", "CREATE"],
                                ),
                            ),
                            AccessPolicyEntry(
                                tenant_id=tenant_id,
                                object_id=str(managed_identity.principal_id),
                                permissions=Permissions(
                                    secrets=["GET", "LIST"],
                                    certificates=["GET", "LIST"],
                                ),
                            ),
                        ],
                    ),
                ),
            )
            # Cast to correct spurious type hint in Azure libraries
            key_vaults = [
                kv
                for kv in cast(list[Vault], key_vault_client.vaults.list())
                if kv.name == key_vault_name
            ]
            self.logger.info(
                f"Ensured that key vault [green]{key_vaults[0].name}[/] exists.",
            )
            return key_vaults[0]
        except Exception as exc:
            msg = f"Failed to create key vault {key_vault_name}.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

    def ensure_keyvault_key(
        self,
        key_name: str,
        key_vault_name: str,
    ) -> KeyVaultKey:
        """Ensure that a key exists in the KeyVault

        Returns:
            str: The key ID

        Raises:
            DataSafeHavenAzureError if the existence of the key could not be verified
        """
        try:
            # Connect to Azure clients
            key_client = KeyClient(
                f"https://{key_vault_name}.vault.azure.net", self.credential
            )

            # Ensure that key exists
            self.logger.debug(
                f"Ensuring that key [green]{key_name}[/] exists...",
            )
            key = None
            try:
                key = key_client.get_key(key_name)
            except (HttpResponseError, ResourceNotFoundError):
                key_client.create_rsa_key(key_name, size=2048)
                key = key_client.get_key(key_name)
            self.logger.info(
                f"Ensured that key [green]{key_name}[/] exists.",
            )
            return key
        except Exception as exc:
            msg = f"Failed to create key {key_name}.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

    def ensure_keyvault_secret(
        self, key_vault_name: str, secret_name: str, secret_value: str
    ) -> KeyVaultSecret:
        """Ensure that a secret exists in the KeyVault

        Returns:
            str: The secret value

        Raises:
            DataSafeHavenAzureError if the existence of the secret could not be verified
        """
        # Ensure that key exists
        self.logger.debug(
            f"Ensuring that secret [green]{secret_name}[/] exists...",
        )
        try:
            # Connect to Azure clients
            secret_client = SecretClient(
                f"https://{key_vault_name}.vault.azure.net", self.credential
            )
            try:
                secret = secret_client.get_secret(secret_name)
            except DataSafeHavenAzureError:
                secret = None
            if not secret:
                self.set_keyvault_secret(key_vault_name, secret_name, secret_value)
                secret = secret_client.get_secret(secret_name)
            self.logger.info(
                f"Ensured that secret [green]{secret_name}[/] exists.",
            )
            return secret
        except Exception as exc:
            msg = f"Failed to create secret {secret_name}.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

    def ensure_keyvault_self_signed_certificate(
        self,
        certificate_name: str,
        certificate_url: str,
        key_vault_name: str,
    ) -> KeyVaultCertificate:
        """Ensure that a self-signed certificate exists in the KeyVault

        Returns:
            KeyVaultCertificate: The self-signed certificate

        Raises:
            DataSafeHavenAzureError if the existence of the certificate could not be verified
        """
        try:
            # Connect to Azure clients
            certificate_client = CertificateClient(
                vault_url=f"https://{key_vault_name}.vault.azure.net",
                credential=self.credential,
            )

            # Ensure that certificate exists
            self.logger.debug(
                f"Ensuring that certificate [green]{certificate_url}[/] exists...",
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
            poller: LROPoller[
                KeyVaultCertificate
            ] = certificate_client.begin_create_certificate(
                certificate_name=certificate_name, policy=policy
            )
            certificate = poller.result()
            self.logger.info(
                f"Ensured that certificate [green]{certificate_url}[/] exists.",
            )
            return certificate
        except Exception as exc:
            msg = f"Failed to create certificate '{certificate_url}'."
            raise DataSafeHavenAzureError(msg) from exc

    def ensure_managed_identity(
        self,
        identity_name: str,
        location: str,
        resource_group_name: str,
    ) -> Identity:
        """Ensure that a managed identity exists

        Returns:
            Identity: The managed identity

        Raises:
            DataSafeHavenAzureError if the existence of the managed identity could not be verified
        """
        try:
            self.logger.debug(
                f"Ensuring that managed identity [green]{identity_name}[/] exists...",
            )
            msi_client = ManagedServiceIdentityClient(
                self.credential, self.subscription_id
            )
            managed_identity = msi_client.user_assigned_identities.create_or_update(
                resource_group_name,
                identity_name,
                Identity(location=location),
            )
            self.logger.info(
                f"Ensured that managed identity [green]{identity_name}[/] exists.",
            )
            return managed_identity
        except Exception as exc:
            msg = f"Failed to create managed identity {identity_name}.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

    def ensure_resource_group(
        self,
        location: str,
        resource_group_name: str,
        tags: Any = None,
    ) -> ResourceGroup:
        """Ensure that a resource group exists

        Raises:
            DataSafeHavenAzureError if the existence of the resource group could not be verified
        """
        try:
            # Connect to Azure clients
            resource_client = ResourceManagementClient(
                self.credential, self.subscription_id
            )

            # Ensure that resource group exists
            self.logger.debug(
                f"Ensuring that resource group [green]{resource_group_name}[/] exists...",
            )
            resource_client.resource_groups.create_or_update(
                resource_group_name,
                ResourceGroup(location=location, tags=tags),
            )
            # Cast to correct spurious type hint in Azure libraries
            resource_groups = [
                rg
                for rg in cast(
                    list[ResourceGroup], resource_client.resource_groups.list()
                )
                if rg.name == resource_group_name
            ]
            self.logger.info(
                f"Ensured that resource group [green]{resource_groups[0].name}[/] exists"
                f" in [green]{resource_groups[0].location}[/].",
            )
            return resource_groups[0]
        except Exception as exc:
            msg = f"Failed to create resource group {resource_group_name}.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

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
            DataSafeHavenAzureError if the existence of the certificate could not be verified
        """
        try:
            # Connect to Azure clients
            storage_client = StorageManagementClient(
                self.credential, self.subscription_id
            )
            self.logger.debug(
                f"Ensuring that storage account [green]{storage_account_name}[/] exists...",
            )
            poller = storage_client.storage_accounts.begin_create(
                resource_group_name,
                storage_account_name,
                StorageAccountCreateParameters(
                    sku=StorageAccountSku(name="Standard_LRS"),
                    kind=StorageAccountKind.STORAGE_V2,
                    location=location,
                    tags=tags,
                ),
            )
            storage_account = poller.result()
            self.logger.info(
                f"Ensured that storage account [green]{storage_account.name}[/] exists.",
            )
            return storage_account
        except Exception as exc:
            msg = f"Failed to create storage account {storage_account_name}.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

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
            DataSafeHavenAzureError if the existence of the certificate could not be verified
        """
        # Connect to Azure clients
        storage_client = StorageManagementClient(self.credential, self.subscription_id)

        self.logger.debug(
            f"Ensuring that storage container [green]{container_name}[/] exists...",
        )
        try:
            container = storage_client.blob_containers.create(
                resource_group_name,
                storage_account_name,
                container_name,
                BlobContainer(public_access=PublicAccess.NONE),
            )
            self.logger.info(
                f"Ensured that storage container [green]{container.name}[/] exists.",
            )
            return container
        except HttpResponseError as exc:
            msg = f"Failed to create storage container [green]{container_name}."
            raise DataSafeHavenAzureError(msg) from exc

    def get_keyvault_certificate(
        self, certificate_name: str, key_vault_name: str
    ) -> KeyVaultCertificate:
        """Read a certificate from the KeyVault

        Returns:
            KeyVaultCertificate: The certificate

        Raises:
            DataSafeHavenAzureError if the secret could not be read
        """
        # Connect to Azure clients
        certificate_client = CertificateClient(
            vault_url=f"https://{key_vault_name}.vault.azure.net",
            credential=self.credential,
        )
        # Ensure that certificate exists
        try:
            return certificate_client.get_certificate(certificate_name)
        except Exception as exc:
            msg = f"Failed to retrieve certificate {certificate_name}."
            raise DataSafeHavenAzureError(msg) from exc

    def get_keyvault_secret(self, key_vault_name: str, secret_name: str) -> str:
        """Read a secret from the KeyVault

        Returns:
            str: The secret value

        Raises:
            DataSafeHavenAzureError if the secret could not be read
        """
        # Connect to Azure clients
        secret_client = SecretClient(
            f"https://{key_vault_name}.vault.azure.net", self.credential
        )
        # Ensure that secret exists
        try:
            secret = secret_client.get_secret(secret_name)
            if secret.value:
                return str(secret.value)
            msg = f"Secret {secret_name} has no value."
            raise DataSafeHavenAzureError(msg)
        except Exception as exc:
            msg = f"Failed to retrieve secret {secret_name}."
            raise DataSafeHavenAzureError(msg) from exc

    def get_locations(self) -> list[str]:
        """Retrieve list of Azure locations

        Returns:
            List[str]: Names of Azure locations
        """
        try:
            subscription_client = SubscriptionClient(self.credential)
            return [
                str(location.name)
                for location in cast(
                    list[Location],
                    subscription_client.subscriptions.list_locations(
                        subscription_id=self.subscription_id
                    ),
                )
            ]
        except Exception as exc:
            msg = f"Azure locations could not be loaded.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

    def get_storage_account_keys(
        self, resource_group_name: str, storage_account_name: str
    ) -> list[StorageAccountKey]:
        """Retrieve the storage account keys for an existing storage account

        Returns:
            List[StorageAccountKey]: The keys for this storage account

        Raises:
            DataSafeHavenAzureError if the keys could not be loaded
        """
        # Connect to Azure client
        try:
            storage_client = StorageManagementClient(
                self.credential, self.subscription_id
            )
            storage_keys = storage_client.storage_accounts.list_keys(
                resource_group_name,
                storage_account_name,
            )
            if not isinstance(storage_keys, StorageAccountListKeysResult):
                msg = (
                    f"Could not connect to storage account '{storage_account_name}'"
                    f" in resource group '{resource_group_name}'."
                )
                raise DataSafeHavenAzureError(msg)
            keys = storage_keys.keys
            if not keys or not isinstance(keys, list) or len(keys) == 0:
                msg = (
                    f"No keys were retrieved for storage account '{storage_account_name}'"
                    f" in resource group '{resource_group_name}'."
                )
                raise DataSafeHavenAzureError(msg)
            return keys
        except Exception as exc:
            msg = (
                f"Keys could not be loaded for storage account '{storage_account_name}'"
                f" in resource group '{resource_group_name}'.\n{exc}"
            )
            raise DataSafeHavenAzureError(msg) from exc

    def get_vm_sku_details(self, sku: str) -> tuple[str, str, str]:
        # Connect to Azure client
        cpus, gpus, ram = None, None, None
        compute_client = ComputeManagementClient(self.credential, self.subscription_id)
        for resource_sku in compute_client.resource_skus.list():
            if resource_sku.name == sku:
                if resource_sku.capabilities:
                    # Cast to correct spurious type hint in Azure libraries
                    for capability in cast(
                        list[ResourceSkuCapabilities], resource_sku.capabilities
                    ):
                        if capability.name == "vCPUs":
                            cpus = capability.value
                        if capability.name == "GPUs":
                            gpus = capability.value
                        if capability.name == "MemoryGB":
                            ram = capability.value
        if cpus and gpus and ram:
            return (cpus, gpus, ram)
        msg = f"Could not find information for VM SKU {sku}."
        raise DataSafeHavenAzureError(msg)

    def import_keyvault_certificate(
        self,
        certificate_name: str,
        certificate_contents: bytes,
        key_vault_name: str,
    ) -> KeyVaultCertificate:
        """Import a signed certificate to in the KeyVault

        Returns:
            KeyVaultCertificate: The imported certificate

        Raises:
            DataSafeHavenAzureError if the existence of the certificate could not be verified
        """
        try:
            # Connect to Azure clients
            certificate_client = CertificateClient(
                vault_url=f"https://{key_vault_name}.vault.azure.net",
                credential=self.credential,
            )
            # Import the certificate, overwriting any existing certificate with the same name
            self.logger.debug(
                f"Importing certificate [green]{certificate_name}[/]...",
            )
            while True:
                try:
                    # Attempt to import this certificate into the keyvault
                    certificate = certificate_client.import_certificate(
                        certificate_name=certificate_name,
                        certificate_bytes=certificate_contents,
                        enabled=True,
                    )
                    break
                except ResourceExistsError:
                    # Purge any existing deleted certificate with the same name
                    self.purge_keyvault_certificate(certificate_name, key_vault_name)
            self.logger.info(
                f"Imported certificate [green]{certificate_name}[/].",
            )
            return certificate
        except Exception as exc:
            msg = f"Failed to import certificate '{certificate_name}'."
            raise DataSafeHavenAzureError(msg) from exc

    def list_available_vm_skus(self, location: str) -> dict[str, dict[str, Any]]:
        try:
            # Connect to Azure client
            compute_client = ComputeManagementClient(
                self.credential, self.subscription_id
            )
            # Construct SKU information
            skus = {}
            for resource_sku in compute_client.resource_skus.list():
                if (
                    resource_sku.locations
                    and (location in resource_sku.locations)
                    and (resource_sku.resource_type == "virtualMachines")
                ):
                    skus[resource_sku.name] = {
                        "GPUs": 0
                    }  # default to 0 GPUs, overriding if appropriate
                    if resource_sku.capabilities:
                        # Cast to correct spurious type hint in Azure libraries
                        for capability in cast(
                            list[ResourceSkuCapabilities], resource_sku.capabilities
                        ):
                            skus[resource_sku.name][capability.name] = capability.value
            return skus
        except Exception as exc:
            msg = f"Failed to load available VM sizes for Azure location {location}.\n{exc}"
            raise DataSafeHavenAzureError(
                msg,
            ) from exc

    def purge_keyvault_certificate(
        self,
        certificate_name: str,
        key_vault_name: str,
    ) -> None:
        """Purge a deleted certificate from the KeyVault

        Raises:
            DataSafeHavenAzureError if the existence of the certificate could not be verified
        """
        try:
            # Connect to Azure clients
            certificate_client = CertificateClient(
                vault_url=f"https://{key_vault_name}.vault.azure.net",
                credential=self.credential,
            )
            # Ensure that record is removed
            self.logger.debug(
                f"Purging certificate [green]{certificate_name}[/] from Key Vault [green]{key_vault_name}[/]...",
            )
            # Purge the certificate
            with suppress(HttpResponseError):
                certificate_client.purge_deleted_certificate(certificate_name)
            # Wait until certificate no longer exists
            while True:
                try:
                    time.sleep(10)
                    certificate_client.get_deleted_certificate(certificate_name)
                except ResourceNotFoundError:
                    break
            self.logger.info(
                f"Purged certificate [green]{certificate_name}[/] from Key Vault [green]{key_vault_name}[/].",
            )
        except Exception as exc:
            msg = f"Failed to remove certificate '{certificate_name}' from Key Vault '{key_vault_name}'."
            raise DataSafeHavenAzureError(
                msg,
            ) from exc

    def remove_dns_txt_record(
        self,
        record_name: str,
        resource_group_name: str,
        zone_name: str,
    ) -> None:
        """Remove a DNS record if it exists in a DNS zone

        Raises:
            DataSafeHavenAzureError if the record could not be removed
        """
        try:
            # Connect to Azure clients
            dns_client = DnsManagementClient(self.credential, self.subscription_id)
            # Ensure that record is removed
            self.logger.debug(
                f"Ensuring that DNS record [green]{record_name}[/] is removed from zone [green]{zone_name}[/]...",
            )
            dns_client.record_sets.delete(
                record_type="TXT",
                relative_record_set_name=record_name,
                resource_group_name=resource_group_name,
                zone_name=zone_name,
            )
            self.logger.info(
                f"Ensured that DNS record [green]{record_name}[/] is removed from zone [green]{zone_name}[/].",
            )
        except Exception as exc:
            msg = f"Failed to remove DNS record [green]{record_name}[/] from zone [green]{zone_name}[/].\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

    def remove_keyvault_certificate(
        self,
        certificate_name: str,
        key_vault_name: str,
    ) -> None:
        """Remove a certificate from the KeyVault

        Raises:
            DataSafeHavenAzureError if the existence of the certificate could not be verified
        """
        try:
            # Connect to Azure clients
            certificate_client = CertificateClient(
                vault_url=f"https://{key_vault_name}.vault.azure.net",
                credential=self.credential,
            )
            # Remove certificate if it exists
            self.logger.debug(
                f"Removing certificate [green]{certificate_name}[/] from Key Vault [green]{key_vault_name}[/]...",
            )
            # Attempt to delete the certificate, catching the error if it does not exist
            with suppress(ResourceNotFoundError):
                # Start by attempting to purge in case the certificate has been manually deleted
                with suppress(HttpResponseError):
                    certificate_client.purge_deleted_certificate(certificate_name)
                # Now delete and keep polling until done
                poller = certificate_client.begin_delete_certificate(certificate_name)
                while not poller.done():
                    poller.wait(10)
                # Purge the deleted certificate
                with suppress(HttpResponseError):
                    certificate_client.purge_deleted_certificate(certificate_name)
            self.logger.info(
                f"Removed certificate [green]{certificate_name}[/] from Key Vault [green]{key_vault_name}[/].",
            )
        except ResourceNotFoundError:
            pass
        except Exception as exc:
            msg = f"Failed to remove certificate '{certificate_name}' from Key Vault '{key_vault_name}'."
            raise DataSafeHavenAzureError(
                msg,
            ) from exc

    def remove_resource_group(self, resource_group_name: str) -> None:
        """Remove a resource group with its contents

        Raises:
            DataSafeHavenAzureError if the resource group could not be removed
        """
        try:
            # Connect to Azure clients
            resource_client = ResourceManagementClient(
                self.credential, self.subscription_id
            )

            # Ensure that resource group exists
            self.logger.debug(
                f"Removing resource group [green]{resource_group_name}[/] if it exists...",
            )
            poller = resource_client.resource_groups.begin_delete(
                resource_group_name,
            )
            while not poller.done():
                poller.wait(10)
            # Cast to correct spurious type hint in Azure libraries
            resource_groups = [
                rg
                for rg in cast(
                    list[ResourceGroup], resource_client.resource_groups.list()
                )
                if rg.name == resource_group_name
            ]
            if resource_groups:
                msg = f"There are still {len(resource_groups)} resource group(s) remaining."
                raise DataSafeHavenInternalError(msg)
            self.logger.info(
                f"Ensured that resource group [green]{resource_group_name}[/] does not exist.",
            )
        except Exception as exc:
            msg = f"Failed to remove resource group {resource_group_name}.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

    def restart_virtual_machine(self, resource_group_name: str, vm_name: str) -> None:
        try:
            self.logger.debug(
                f"Attempting to restart virtual machine '[green]{vm_name}[/]'"
                f" in resource group '[green]{resource_group_name}[/]'...",
            )
            # Connect to Azure clients
            compute_client = ComputeManagementClient(
                self.credential, self.subscription_id
            )
            poller = compute_client.virtual_machines.begin_restart(
                resource_group_name, vm_name
            )
            _ = (
                poller.result()
            )  # returns 'None' on success or raises an exception on failure
            self.logger.info(
                f"Restarted virtual machine '[green]{vm_name}[/]' in resource group '[green]{resource_group_name}[/]'.",
            )
        except Exception as exc:
            msg = f"Failed to restart virtual machine '{vm_name}' in resource group '{resource_group_name}'.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

    def run_remote_script(
        self,
        resource_group_name: str,
        script: str,
        script_parameters: dict[str, str],
        vm_name: str,
    ) -> str:
        """Run a script on a remote virtual machine

        Returns:
            str: The script output

        Raises:
            DataSafeHavenAzureError if running the script failed
        """
        try:
            # Connect to Azure clients
            compute_client = ComputeManagementClient(
                self.credential, self.subscription_id
            )
            vm = compute_client.virtual_machines.get(resource_group_name, vm_name)
            if not vm.os_profile:
                msg = f"No OSProfile available for VM {vm_name}"
                raise ValueError(msg)
            command_id = (
                "RunPowerShellScript"
                if (
                    vm.os_profile.windows_configuration
                    and not vm.os_profile.linux_configuration
                )
                else "RunShellScript"
            )
            run_command_parameters = RunCommandInput(
                command_id=command_id,
                script=list(script.split("\n")),
                parameters=[
                    RunCommandInputParameter(name=name, value=value)
                    for name, value in script_parameters.items()
                ],
            )
            # Run the command and wait until finished
            poller = compute_client.virtual_machines.begin_run_command(
                resource_group_name, vm_name, run_command_parameters
            )
            # Cast to correct spurious type hint in Azure libraries
            result = cast(RunCommandResult, poller.result())
            # Return any stdout/stderr from the command
            return str(result.value[0].message) if result.value else ""
        except Exception as exc:
            msg = f"Failed to run command on '{vm_name}'.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

    def set_blob_container_acl(
        self,
        container_name: str,
        desired_acl: str,
        resource_group_name: str,
        storage_account_name: str,
    ) -> None:
        """Set the ACL for a blob container

        Raises:
            DataSafeHavenAzureError if the ACL could not be set
        """
        try:
            # Ensure that storage container exists in the storage account
            storage_client = StorageManagementClient(
                self.credential, self.subscription_id
            )
            try:
                container = storage_client.blob_containers.get(
                    resource_group_name, storage_account_name, container_name
                )
                if container.name != container_name:
                    msg = "Container could not be found."
                    raise HttpResponseError(msg)
            except HttpResponseError:
                self.logger.warning(
                    f"Blob container '[green]{container_name}[/]' could not be found"
                    f" in storage account '[green]{storage_account_name}[/]'."
                )
                return

            # Connect to Azure clients
            service_client = DataLakeServiceClient(
                f"https://{storage_account_name}.dfs.core.windows.net", self.credential
            )
            file_system_client = service_client.get_file_system_client(
                file_system=container_name
            )
            directory_client = file_system_client._get_root_directory_client()
            # Set the desired ACL
            directory_client.set_access_control_recursive(acl=desired_acl)
        except Exception as exc:
            msg = f"Failed to set ACL '{desired_acl}' on container '{container_name}'.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

    def set_keyvault_secret(
        self, key_vault_name: str, secret_name: str, secret_value: str
    ) -> KeyVaultSecret:
        """Ensure that a KeyVault secret has the desired value

        Returns:
            str: The secret value

        Raises:
            DataSafeHavenAzureError if the secret could not be set
        """
        try:
            # Connect to Azure clients
            secret_client = SecretClient(
                f"https://{key_vault_name}.vault.azure.net", self.credential
            )
            # Set the secret to the desired value
            try:
                existing_value = secret_client.get_secret(secret_name).value
            except ResourceNotFoundError:
                existing_value = None
            if (not existing_value) or (existing_value != secret_value):
                secret_client.set_secret(secret_name, secret_value)
            return secret_client.get_secret(secret_name)
        except Exception as exc:
            msg = f"Failed to set secret '{secret_name}'.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

    def upload_blob(
        self,
        blob_data: bytes | str,
        blob_name: str,
        resource_group_name: str,
        storage_account_name: str,
        storage_container_name: str,
    ) -> None:
        """Upload a file to Azure blob storage

        Returns:
            None

        Raises:
            DataSafeHavenAzureError if the blob could not be uploaded
        """
        try:
            # Connect to Azure client
            storage_account_keys = self.get_storage_account_keys(
                resource_group_name, storage_account_name
            )
            blob_service_client = BlobServiceClient.from_connection_string(
                f"DefaultEndpointsProtocol=https;AccountName={storage_account_name};AccountKey={storage_account_keys[0].value};EndpointSuffix=core.windows.net"
            )
            if not isinstance(blob_service_client, BlobServiceClient):
                msg = f"Could not connect to storage account '{storage_account_name}'."
                raise DataSafeHavenAzureError(msg)
            # Upload the created file
            blob_client = blob_service_client.get_blob_client(
                container=storage_container_name, blob=blob_name
            )
            blob_client.upload_blob(blob_data, overwrite=True)
            self.logger.info(
                f"Uploaded file [green]{blob_name}[/] to blob storage.",
            )
        except Exception as exc:
            msg = f"Blob file '{blob_name}' could not be uploaded to '{storage_account_name}'\n{exc}."
            raise DataSafeHavenAzureError(msg) from exc
