"""Interface to the Azure Python SDK"""

import time
from contextlib import suppress
from typing import Any, cast

from azure.core.exceptions import (
    AzureError,
    ClientAuthenticationError,
    HttpResponseError,
    ResourceExistsError,
    ResourceNotFoundError,
    ServiceRequestError,
)
from azure.keyvault.certificates import CertificateClient, KeyVaultCertificate
from azure.keyvault.keys import KeyClient, KeyVaultKey
from azure.keyvault.secrets import SecretClient
from azure.mgmt.compute.v2021_07_01 import ComputeManagementClient
from azure.mgmt.compute.v2021_07_01.models import (
    ResourceSkuCapabilities,
    RunCommandInput,
    RunCommandInputParameter,
    RunCommandResult,
)
from azure.mgmt.dns.v2018_05_01 import DnsManagementClient
from azure.mgmt.dns.v2018_05_01.models import (
    CaaRecord,
    RecordSet,
    RecordType,
    TxtRecord,
    Zone,
    ZoneType,
)
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
from azure.mgmt.resource.subscriptions.models import Location, Subscription
from azure.mgmt.storage.v2021_08_01 import StorageManagementClient
from azure.mgmt.storage.v2021_08_01.models import (
    BlobContainer,
    Kind as StorageAccountKind,
    MinimumTlsVersion,
    PublicAccess,
    Sku as StorageAccountSku,
    StorageAccount,
    StorageAccountCreateParameters,
    StorageAccountKey,
    StorageAccountListKeysResult,
)
from azure.storage.blob import BlobClient, BlobServiceClient
from azure.storage.filedatalake import DataLakeServiceClient

from data_safe_haven.exceptions import (
    DataSafeHavenAzureAPIAuthenticationError,
    DataSafeHavenAzureError,
    DataSafeHavenAzureStorageError,
    DataSafeHavenValueError,
)
from data_safe_haven.logging import get_logger, get_null_logger
from data_safe_haven.types import AzureSdkCredentialScope

from .credentials import AzureSdkCredential
from .graph_api import GraphApi


class AzureSdk:
    """Interface to the Azure Python SDK"""

    def __init__(
        self, subscription_name: str, *, disable_logging: bool = False
    ) -> None:
        self._credentials: dict[AzureSdkCredentialScope, AzureSdkCredential] = {}
        self.disable_logging = disable_logging
        self.logger = get_null_logger() if disable_logging else get_logger()
        self.subscription_name = subscription_name
        self.subscription_id_: str | None = None
        self.tenant_id_: str | None = None

    @property
    def entra_directory(self) -> GraphApi:
        return GraphApi(credential=self.credential(AzureSdkCredentialScope.GRAPH_API))

    @property
    def subscription_id(self) -> str:
        if not self.subscription_id_:
            self.subscription_id_ = str(
                self.get_subscription(self.subscription_name).subscription_id
            )
        return self.subscription_id_

    @property
    def tenant_id(self) -> str:
        if not self.tenant_id_:
            self.tenant_id_ = str(
                self.get_subscription(self.subscription_name).tenant_id
            )
        return self.tenant_id_

    def blob_client(
        self,
        resource_group_name: str,
        storage_account_name: str,
        storage_container_name: str,
        blob_name: str,
    ) -> BlobClient:
        try:
            # Get the blob client from the blob service client
            blob_service_client = self.blob_service_client(
                resource_group_name, storage_account_name
            )
            blob_client = blob_service_client.get_blob_client(
                container=storage_container_name, blob=blob_name
            )
            if not isinstance(blob_client, BlobClient):
                msg = f"Blob client has incorrect type {type(blob_client)}."
                raise TypeError(msg)
            return blob_client
        except (DataSafeHavenAzureStorageError, TypeError) as exc:
            msg = f"Could not load blob client for storage account '{storage_account_name}'."
            raise DataSafeHavenAzureStorageError(msg) from exc

    def blob_exists(
        self,
        blob_name: str,
        resource_group_name: str,
        storage_account_name: str,
        storage_container_name: str,
    ) -> bool:
        """Find out whether a blob file exists in Azure storage

        Returns:
            bool: Whether or not the blob exists
        """

        if not self.storage_exists(storage_account_name):
            msg = f"Storage account '{storage_account_name}' could not be found."
            raise DataSafeHavenAzureStorageError(msg)
        try:
            blob_client = self.blob_client(
                resource_group_name,
                storage_account_name,
                storage_container_name,
                blob_name,
            )
            exists = bool(blob_client.exists())
        except DataSafeHavenAzureStorageError:
            exists = False
        response = "exists" if exists else "does not exist"
        self.logger.debug(
            f"File [green]{blob_name}[/] {response} in blob storage.",
        )
        return exists

    def blob_service_client(
        self,
        resource_group_name: str,
        storage_account_name: str,
    ) -> BlobServiceClient:
        """Construct a client for a blob which may exist or not"""
        try:
            # Connect to Azure client
            storage_account_keys = self.get_storage_account_keys(
                resource_group_name, storage_account_name
            )
            # Load blob service client
            blob_service_client = BlobServiceClient.from_connection_string(
                ";".join(
                    (
                        "DefaultEndpointsProtocol=https",
                        f"AccountName={storage_account_name}",
                        f"AccountKey={storage_account_keys[0].value}",
                        "EndpointSuffix=core.windows.net",
                    )
                )
            )
            if not isinstance(blob_service_client, BlobServiceClient):
                msg = f"Blob service client has incorrect type {type(blob_service_client)}."
                raise TypeError(msg)
            return blob_service_client
        except (AzureError, TypeError) as exc:
            msg = f"Could not load blob service client for storage account '{storage_account_name}'."
            raise DataSafeHavenAzureStorageError(msg) from exc

    def credential(
        self, scope: AzureSdkCredentialScope = AzureSdkCredentialScope.DEFAULT
    ) -> AzureSdkCredential:
        if scope not in self._credentials:
            self._credentials[scope] = AzureSdkCredential(
                scope, skip_confirmation=self.disable_logging
            )
        return self._credentials[scope]

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
            # Get the blob client
            blob_client = self.blob_client(
                resource_group_name,
                storage_account_name,
                storage_container_name,
                blob_name,
            )
            # Download the requested file
            blob_content = blob_client.download_blob(encoding="utf-8").readall()
            self.logger.debug(
                f"Downloaded file [green]{blob_name}[/] from blob storage.",
            )
            return str(blob_content)
        except (AzureError, DataSafeHavenAzureStorageError) as exc:
            msg = f"Blob file '{blob_name}' could not be downloaded from '{storage_account_name}'."
            raise DataSafeHavenAzureError(msg) from exc

    def ensure_dns_caa_record(
        self,
        record_flags: int,
        record_name: str,
        record_tag: str,
        record_value: str,
        resource_group_name: str,
        zone_name: str,
        ttl: int = 30,
    ) -> RecordSet:
        """Ensure that a DNS CAA record exists in a DNS zone

        Returns:
            RecordSet: The DNS record set

        Raises:
            DataSafeHavenAzureError if the record could not be created
        """
        try:
            # Connect to Azure clients
            dns_client = DnsManagementClient(self.credential(), self.subscription_id)

            # Ensure that record exists
            self.logger.debug(
                f"Ensuring that DNS CAA record [green]{record_name}[/] exists in zone [bold]{zone_name}[/]...",
            )
            record_set = dns_client.record_sets.create_or_update(
                parameters=RecordSet(
                    ttl=ttl,
                    caa_records=[
                        CaaRecord(
                            flags=record_flags, tag=record_tag, value=record_value
                        )
                    ],
                ),
                record_type=RecordType.CAA,
                relative_record_set_name=record_name,
                resource_group_name=resource_group_name,
                zone_name=zone_name,
            )
            self.logger.info(
                f"Ensured that DNS CAA record [green]{record_name}[/] exists in zone [bold]{zone_name}[/].",
            )
            return record_set
        except AzureError as exc:
            msg = f"Failed to create DNS CAA record {record_name} in zone {zone_name}.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc

    def ensure_dns_txt_record(
        self,
        record_name: str,
        record_value: str,
        resource_group_name: str,
        zone_name: str,
        ttl: int = 30,
    ) -> RecordSet:
        """Ensure that a DNS TXT record exists in a DNS zone

        Returns:
            RecordSet: The DNS record set

        Raises:
            DataSafeHavenAzureError if the record could not be created
        """
        try:
            # Connect to Azure clients
            dns_client = DnsManagementClient(self.credential(), self.subscription_id)

            # Ensure that record exists
            self.logger.debug(
                f"Ensuring that DNS TXT record [green]{record_name}[/] exists in zone [bold]{zone_name}[/]...",
            )
            record_set = dns_client.record_sets.create_or_update(
                parameters=RecordSet(
                    ttl=ttl, txt_records=[TxtRecord(value=[record_value])]
                ),
                record_type=RecordType.TXT,
                relative_record_set_name=record_name,
                resource_group_name=resource_group_name,
                zone_name=zone_name,
            )
            self.logger.info(
                f"Ensured that DNS TXT record [green]{record_name}[/] exists in zone [bold]{zone_name}[/].",
            )
            return record_set
        except AzureError as exc:
            msg = f"Failed to create DNS TXT record {record_name} in zone {zone_name}."
            raise DataSafeHavenAzureError(msg) from exc

    def ensure_dns_zone(
        self,
        resource_group_name: str,
        zone_name: str,
        tags: Any = None,
    ) -> Zone:
        """Ensure that a DNS zone exists

        Returns:
            Zone: The DNS zone

        Raises:
            DataSafeHavenAzureError if the zone could not be created
        """
        try:
            # Connect to Azure clients
            dns_client = DnsManagementClient(self.credential(), self.subscription_id)

            # Ensure that record exists
            self.logger.debug(
                f"Ensuring that DNS zone {zone_name} exists...",
            )
            zone = dns_client.zones.create_or_update(
                parameters=Zone(
                    location="Global",
                    tags=tags,
                    zone_type=ZoneType.PUBLIC,
                ),
                resource_group_name=resource_group_name,
                zone_name=zone_name,
            )
            self.logger.info(
                f"Ensured that DNS zone [green]{zone_name}[/] exists.",
            )
            return zone
        except AzureError as exc:
            msg = f"Failed to create DNS zone {zone_name}.\n{exc}"
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
                self.credential(), self.subscription_id
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
        except AzureError as exc:
            msg = f"Failed to create key vault {key_vault_name}."
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
                credential=self.credential(AzureSdkCredentialScope.KEY_VAULT),
                vault_url=f"https://{key_vault_name}.vault.azure.net",
            )

            # Ensure that key exists
            self.logger.debug(f"Ensuring that key [green]{key_name}[/] exists...")
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
        except AzureError as exc:
            msg = f"Failed to create key {key_name}."
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
                self.credential(), self.subscription_id
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
        except AzureError as exc:
            msg = f"Failed to create managed identity {identity_name}."
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
                self.credential(), self.subscription_id
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
        except AzureError as exc:
            msg = f"Failed to create resource group {resource_group_name}."
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
                self.credential(), self.subscription_id
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
                    minimum_tls_version=MinimumTlsVersion.TLS1_2,
                ),
            )
            storage_account = poller.result()
            self.logger.info(
                f"Ensured that storage account [green]{storage_account.name}[/] exists.",
            )
            return storage_account
        except AzureError as exc:
            msg = f"Failed to create storage account {storage_account_name}."
            raise DataSafeHavenAzureStorageError(msg) from exc

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
        storage_client = StorageManagementClient(
            self.credential(), self.subscription_id
        )

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
            msg = f"Failed to create storage container '{container_name}'."
            raise DataSafeHavenAzureStorageError(msg) from exc

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
            credential=self.credential(AzureSdkCredentialScope.KEY_VAULT),
            vault_url=f"https://{key_vault_name}.vault.azure.net",
        )
        # Ensure that certificate exists
        try:
            return certificate_client.get_certificate(certificate_name)
        except AzureError as exc:
            msg = f"Failed to retrieve certificate {certificate_name}."
            raise DataSafeHavenAzureError(msg) from exc

    def get_keyvault_key(self, key_name: str, key_vault_name: str) -> KeyVaultKey:
        """Read a key from the KeyVault

        Returns:
            KeyVaultKey: The key

        Raises:
            DataSafeHavenAzureError if the secret could not be read
        """
        # Connect to Azure clients
        key_client = KeyClient(
            credential=self.credential(AzureSdkCredentialScope.KEY_VAULT),
            vault_url=f"https://{key_vault_name}.vault.azure.net",
        )
        # Ensure that certificate exists
        try:
            return key_client.get_key(key_name)
        except (ResourceNotFoundError, HttpResponseError) as exc:
            msg = f"Failed to retrieve key {key_name}."
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
            credential=self.credential(AzureSdkCredentialScope.KEY_VAULT),
            vault_url=f"https://{key_vault_name}.vault.azure.net",
        )
        # Ensure that secret exists
        try:
            secret = secret_client.get_secret(secret_name)
            if secret.value:
                return str(secret.value)
            msg = f"Secret {secret_name} has no value."
            raise DataSafeHavenAzureError(msg)
        except AzureError as exc:
            msg = f"Failed to retrieve secret {secret_name}."
            raise DataSafeHavenAzureError(msg) from exc

    def get_locations(self) -> list[str]:
        """Retrieve list of Azure locations

        Returns:
            List[str]: Names of Azure locations
        """
        try:
            subscription_client = SubscriptionClient(self.credential())
            return [
                str(location.name)
                for location in cast(
                    list[Location],
                    subscription_client.subscriptions.list_locations(
                        subscription_id=self.subscription_id
                    ),
                )
            ]
        except AzureError as exc:
            msg = "Azure locations could not be loaded."
            raise DataSafeHavenAzureError(msg) from exc

    def get_storage_account_keys(
        self, resource_group_name: str, storage_account_name: str, *, attempts: int = 3
    ) -> list[StorageAccountKey]:
        """Retrieve the storage account keys for an existing storage account

        Returns:
            List[StorageAccountKey]: The keys for this storage account

        Raises:
            DataSafeHavenAzureError if the keys could not be loaded
        """
        msg_sa = f"storage account '{storage_account_name}'"
        msg_rg = f"resource group '{resource_group_name}'"
        try:
            # Connect to Azure client
            storage_client = StorageManagementClient(
                self.credential(), self.subscription_id
            )
            storage_keys = None
            for _ in range(attempts):
                with suppress(HttpResponseError):
                    storage_keys = storage_client.storage_accounts.list_keys(
                        resource_group_name,
                        storage_account_name,
                    )
                if storage_keys:
                    break
                time.sleep(5)
            if not isinstance(storage_keys, StorageAccountListKeysResult):
                msg = f"No keys were retrieved for {msg_sa} in {msg_rg}."
                raise DataSafeHavenAzureStorageError(msg)
            keys = cast(list[StorageAccountKey], storage_keys.keys)
            if not keys or not isinstance(keys, list) or len(keys) == 0:
                msg = f"List of keys was empty for {msg_sa} in {msg_rg}."
                raise DataSafeHavenAzureStorageError(msg)
            return keys
        except AzureError as exc:
            msg = f"Keys could not be loaded for {msg_sa} in {msg_rg}."
            raise DataSafeHavenAzureStorageError(msg) from exc

    def get_subscription(self, subscription_name: str) -> Subscription:
        """Get an Azure subscription by name."""
        try:
            subscription_client = SubscriptionClient(self.credential())
            for subscription in subscription_client.subscriptions.list():
                if subscription.display_name == subscription_name:
                    return subscription
        except ClientAuthenticationError as exc:
            msg = "Failed to authenticate with Azure API."
            raise DataSafeHavenAzureAPIAuthenticationError(msg) from exc
        msg = f"Could not find subscription '{subscription_name}'"
        raise DataSafeHavenValueError(msg)

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
                credential=self.credential(AzureSdkCredentialScope.KEY_VAULT),
                vault_url=f"https://{key_vault_name}.vault.azure.net",
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
        except AzureError as exc:
            msg = f"Failed to import certificate '{certificate_name}'."
            raise DataSafeHavenAzureError(msg) from exc

    def list_available_vm_skus(self, location: str) -> dict[str, dict[str, Any]]:
        try:
            # Connect to Azure client
            compute_client = ComputeManagementClient(
                self.credential(), self.subscription_id
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
        except AzureError as exc:
            msg = f"Failed to load available VM sizes for Azure location {location}."
            raise DataSafeHavenAzureError(msg) from exc

    def list_blobs(
        self,
        container_name: str,
        prefix: str,
        resource_group_name: str,
        storage_account_name: str,
    ) -> list[str]:
        """List all blobs with a given prefix in a container

        Returns:
            List[str]: The list of blob names
        """

        blob_client = self.blob_service_client(
            resource_group_name=resource_group_name,
            storage_account_name=storage_account_name,
        )
        container_client = blob_client.get_container_client(container=container_name)
        blob_list = container_client.list_blob_names(name_starts_with=prefix)
        return list(blob_list)

    def purge_keyvault(
        self,
        key_vault_name: str,
        location: str,
    ) -> bool:
        """Purge a deleted Key Vault from Azure

        Returns:
            True: if the Key Vault was purged from a deleted state
            False: if the Key Vault did not need to be purged

        Raises:
            DataSafeHavenAzureError if the non-existence of the Key Vault could not be verified
        """
        try:
            # Connect to Azure clients
            key_vault_client = KeyVaultManagementClient(
                self.credential(), self.subscription_id
            )

            # Check whether a deleted Key Vault exists
            try:
                key_vault_client.vaults.get_deleted(
                    vault_name=key_vault_name,
                    location=location,
                )
            except HttpResponseError:
                self.logger.info(
                    f"Key Vault [green]{key_vault_name}[/] does not need to be purged."
                )
                return False

            # Purge the Key Vault
            with suppress(HttpResponseError):
                self.logger.debug(
                    f"Purging Key Vault [green]{key_vault_name}[/]...",
                )

                # Keep polling until purge is finished
                poller = key_vault_client.vaults.begin_purge_deleted(
                    vault_name=key_vault_name,
                    location=location,
                )
                while not poller.done():
                    poller.wait(10)

            # Check whether the Key Vault is still in deleted state
            with suppress(HttpResponseError):
                if key_vault_client.vaults.get_deleted(
                    vault_name=key_vault_name,
                    location=location,
                ):
                    msg = f"Key Vault '{key_vault_name}' exists in deleted state."
                    raise AzureError(msg)
            self.logger.info(f"Purged Key Vault [green]{key_vault_name}[/].")
            return True
        except AzureError as exc:
            msg = f"Failed to remove Key Vault '{key_vault_name}'."
            raise DataSafeHavenAzureError(msg) from exc

    def purge_keyvault_certificate(
        self,
        certificate_name: str,
        key_vault_name: str,
    ) -> None:
        """Purge a deleted certificate from the KeyVault

        Raises:
            DataSafeHavenAzureError if the non-existence of the certificate could not be verified
        """
        try:
            # Connect to Azure clients
            certificate_client = CertificateClient(
                credential=self.credential(AzureSdkCredentialScope.KEY_VAULT),
                vault_url=f"https://{key_vault_name}.vault.azure.net",
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
        except AzureError as exc:
            msg = f"Failed to remove certificate '{certificate_name}' from Key Vault '{key_vault_name}'."
            raise DataSafeHavenAzureError(msg) from exc

    def remove_blob(
        self,
        blob_name: str,
        resource_group_name: str,
        storage_account_name: str,
        storage_container_name: str,
    ) -> None:
        """Remove a file from Azure blob storage

        Returns:
            None

        Raises:
            DataSafeHavenAzureError if the blob could not be removed
        """
        try:
            # Get the blob client
            blob_client = self.blob_client(
                resource_group_name=resource_group_name,
                storage_account_name=storage_account_name,
                storage_container_name=storage_container_name,
                blob_name=blob_name,
            )
            # Remove the requested blob
            blob_client.delete_blob(delete_snapshots="include")
            self.logger.info(
                f"Removed file [green]{blob_name}[/] from blob storage.",
            )
        except (AzureError, DataSafeHavenAzureStorageError) as exc:
            msg = f"Blob file '{blob_name}' could not be removed from '{storage_account_name}'."
            raise DataSafeHavenAzureError(msg) from exc

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
            dns_client = DnsManagementClient(self.credential(), self.subscription_id)
            # Check whether resource currently exists
            try:
                dns_client.record_sets.get(
                    record_type=RecordType.TXT,
                    relative_record_set_name=record_name,
                    resource_group_name=resource_group_name,
                    zone_name=zone_name,
                )
            except ResourceNotFoundError:
                self.logger.warning(
                    f"DNS record [green]{record_name}[/] does not exist in zone [green]{zone_name}[/].",
                )
                return
            # Ensure that record is removed
            self.logger.debug(
                f"Ensuring that DNS record [green]{record_name}[/] is removed from zone [green]{zone_name}[/]...",
            )
            dns_client.record_sets.delete(
                record_type=RecordType.TXT,
                relative_record_set_name=record_name,
                resource_group_name=resource_group_name,
                zone_name=zone_name,
            )
            self.logger.info(
                f"Ensured that DNS record [green]{record_name}[/] is removed from zone [green]{zone_name}[/].",
            )
        except AzureError as exc:
            msg = f"Failed to remove DNS record {record_name} from zone {zone_name}."
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
                credential=self.credential(AzureSdkCredentialScope.KEY_VAULT),
                vault_url=f"https://{key_vault_name}.vault.azure.net",
            )
            self.logger.debug(
                f"Removing certificate [green]{certificate_name}[/] from Key Vault [green]{key_vault_name}[/]...",
            )

            # Start by attempting to delete
            # This might fail if the certificate does not exist or was already deleted
            self.logger.debug(
                f"Attempting to delete certificate [green]{certificate_name}[/]..."
            )
            with suppress(ResourceNotFoundError, ServiceRequestError):
                # Keep polling until deletion is finished
                poller = certificate_client.begin_delete_certificate(certificate_name)
                while not poller.done():
                    poller.wait(10)

            # Wait until the certificate shows up as deleted
            self.logger.debug(
                f"Waiting for deletion to complete for certificate [green]{certificate_name}[/]..."
            )
            while True:
                # Keep polling until deleted certificate is available
                with suppress(ResourceNotFoundError):
                    if certificate_client.get_deleted_certificate(certificate_name):
                        break
                time.sleep(10)

            # Now attempt to remove a certificate that has been deleted but not purged
            self.logger.debug(
                f"Attempting to purge certificate [green]{certificate_name}[/]..."
            )
            with suppress(ResourceNotFoundError, ServiceRequestError):
                certificate_client.purge_deleted_certificate(certificate_name)

            # Now check whether the certificate still exists
            self.logger.debug(
                f"Checking for existence of certificate [green]{certificate_name}[/]..."
            )
            with suppress(ResourceNotFoundError, ServiceRequestError):
                certificate_client.get_certificate(certificate_name)
                msg = f"Certificate '{certificate_name}' is still in Key Vault '{key_vault_name}' despite deletion."
                raise DataSafeHavenAzureError(msg)

            self.logger.info(
                f"Removed certificate [green]{certificate_name}[/] from Key Vault [green]{key_vault_name}[/].",
            )
        except AzureError as exc:
            msg = f"Failed to remove certificate '{certificate_name}' from Key Vault '{key_vault_name}'."
            raise DataSafeHavenAzureError(msg) from exc

    def remove_resource_group(self, resource_group_name: str) -> None:
        """Remove a resource group with its contents

        Raises:
            DataSafeHavenAzureError if the resource group could not be removed
        """
        try:
            # Connect to Azure clients
            resource_client = ResourceManagementClient(
                self.credential(), self.subscription_id
            )

            if not resource_client.resource_groups.check_existence(resource_group_name):
                self.logger.warning(
                    f"Resource group [green]{resource_group_name}[/] does not exist.",
                )
                return
            # Ensure that resource group exists
            self.logger.debug(
                f"Attempting to remove resource group [green]{resource_group_name}[/]",
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
                raise DataSafeHavenAzureError(msg)
            self.logger.info(
                f"Ensured that resource group [green]{resource_group_name}[/] does not exist.",
            )
        except AzureError as exc:
            msg = f"Failed to remove resource group {resource_group_name}."
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
                self.credential(), self.subscription_id
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
        except AzureError as exc:
            msg = f"Failed to run command on '{vm_name}'."
            raise DataSafeHavenAzureError(msg) from exc

    def run_remote_script_waiting(
        self,
        resource_group_name: str,
        script: str,
        script_parameters: dict[str, str],
        vm_name: str,
    ) -> str:
        """Run a script on a remote virtual machine waiting for other scripts to complete

        Returns:
            str: The script output

        Raises:
            DataSafeHavenAzureError if running the script failed
        """
        while True:
            try:
                script_output = self.run_remote_script(
                    resource_group_name=resource_group_name,
                    script=script,
                    script_parameters=script_parameters,
                    vm_name=vm_name,
                )
                break
            except AzureError as exc:
                if all(
                    reason not in str(exc)
                    for reason in (
                        "The request failed due to conflict with a concurrent request",
                        "Run command extension execution is in progress",
                    )
                ):
                    raise
                time.sleep(5)
        return script_output

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
                self.credential(), self.subscription_id
            )
            try:
                container = storage_client.blob_containers.get(
                    resource_group_name, storage_account_name, container_name
                )
                if container.name != container_name:
                    msg = f"Container '{container_name}' could not be found."
                    raise HttpResponseError(msg)
            except HttpResponseError:
                self.logger.warning(
                    f"Blob container '[green]{container_name}[/]' could not be found"
                    f" in storage account '[green]{storage_account_name}[/]'."
                )
                return

            # Connect to Azure clients
            service_client = DataLakeServiceClient(
                account_url=f"https://{storage_account_name}.dfs.core.windows.net",
                credential=self.credential(),
            )
            file_system_client = service_client.get_file_system_client(
                file_system=container_name
            )
            directory_client = file_system_client._get_root_directory_client()
            # Set the desired ACL
            directory_client.set_access_control_recursive(acl=desired_acl)
        except AzureError as exc:
            msg = f"Failed to set ACL '{desired_acl}' on container '{container_name}'."
            raise DataSafeHavenAzureError(msg) from exc

    def storage_exists(
        self,
        storage_account_name: str,
    ) -> bool:
        """Find out whether a named storage account exists in the Azure subscription

        Returns:
            bool: Whether or not the storage account exists
        """

        storage_client = StorageManagementClient(
            self.credential(), self.subscription_id
        )
        storage_account_names = {s.name for s in storage_client.storage_accounts.list()}
        return storage_account_name in storage_account_names

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
            # Get the blob client
            blob_client = self.blob_client(
                resource_group_name,
                storage_account_name,
                storage_container_name,
                blob_name,
            )
            # Upload the created file
            blob_client.upload_blob(blob_data, overwrite=True)
            self.logger.debug(
                f"Uploaded file [green]{blob_name}[/] to blob storage.",
            )
        except (AzureError, DataSafeHavenAzureStorageError) as exc:
            msg = f"Blob file '{blob_name}' could not be uploaded to '{storage_account_name}'."
            raise DataSafeHavenAzureError(msg) from exc
