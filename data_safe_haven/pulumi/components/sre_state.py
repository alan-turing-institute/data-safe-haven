"""Pulumi component for SRE state"""
# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import keyvault, managedidentity, resources, storage

# Local imports
from data_safe_haven.helpers import alphanumeric, hash
from ..dynamic.ssl_certificate import SSLCertificate, SSLCertificateProps


class SREStateProps:
    """Properties for SREStateComponent"""

    def __init__(
        self,
        admin_group_id: Input[str],
        admin_email_address: Input[str],
        location: Input[str],
        networking_resource_group_name: Input[str],
        subscription_name: Input[str],
        sre_fqdn: Input[str],
        tenant_id: Input[str],
    ):
        self.admin_email_address = admin_email_address
        self.admin_group_id = admin_group_id
        self.location = location
        self.networking_resource_group_name = networking_resource_group_name
        self.sre_fqdn = sre_fqdn
        self.subscription_name = subscription_name
        self.tenant_id = tenant_id


class SREStateComponent(ComponentResource):
    """Deploy SRE state with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SREStateProps,
        opts: ResourceOptions = None,
    ):
        super().__init__("dsh:sre:SREStateComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"rg-{stack_name}-state",
        )

        # Deploy storage account
        storage_account = storage.StorageAccount(
            f"{self._name}_storage_account_state",
            account_name=alphanumeric(f"sre{sre_name}{hash(stack_name)}")[
                :24
            ],  # maximum of 24 characters
            kind="StorageV2",
            resource_group_name=resource_group.name,
            sku=storage.SkuArgs(name="Standard_LRS"),
        )

        # Retrieve storage account keys
        storage_account_keys = storage.list_storage_account_keys(
            account_name=storage_account.name,
            resource_group_name=resource_group.name,
        )

        # Define Key Vault reader
        key_vault_reader = managedidentity.UserAssignedIdentity(
            f"{self._name}_key_vault_reader",
            location=props.location,
            resource_group_name=resource_group.name,
            resource_name_=f"id-{stack_name}-key-vault-reader",
        )

        # Define SRE KeyVault
        key_vault = keyvault.Vault(
            f"{self._name}_key_vault",
            location=props.location,
            properties=keyvault.VaultPropertiesArgs(
                access_policies=[
                    keyvault.AccessPolicyEntryArgs(
                        object_id=props.admin_group_id,
                        permissions=keyvault.PermissionsArgs(
                            certificates=[
                                "get",
                                "list",
                                "delete",
                                "create",
                                "import",
                                "update",
                                "managecontacts",
                                "getissuers",
                                "listissuers",
                                "setissuers",
                                "deleteissuers",
                                "manageissuers",
                                "recover",
                                "purge",
                            ],
                            keys=[
                                "encrypt",
                                "decrypt",
                                "sign",
                                "verify",
                                "get",
                                "list",
                                "create",
                                "update",
                                "import",
                                "delete",
                                "backup",
                                "restore",
                                "recover",
                                "purge",
                            ],
                            secrets=[
                                "get",
                                "list",
                                "set",
                                "delete",
                                "backup",
                                "restore",
                                "recover",
                                "purge",
                            ],
                        ),
                        tenant_id=props.tenant_id,
                    ),
                    keyvault.AccessPolicyEntryArgs(
                        object_id=key_vault_reader.principal_id,
                        permissions=keyvault.PermissionsArgs(
                            certificates=[
                                "get",
                                "list",
                            ],
                            keys=[
                                "get",
                                "list",
                            ],
                            secrets=[
                                "get",
                                "list",
                            ],
                        ),
                        tenant_id=props.tenant_id,
                    ),
                ],
                enabled_for_deployment=True,
                enabled_for_disk_encryption=True,
                enabled_for_template_deployment=True,
                sku=keyvault.SkuArgs(
                    family="A",
                    name=keyvault.SkuName.STANDARD,
                ),
                tenant_id=props.tenant_id,
            ),
            resource_group_name=resource_group.name,
            vault_name=f"kv-sre-{sre_name[:11]}-state",  # maximum of 24 characters
        )

        # Define SSL certificate for this FQDN
        certificate = SSLCertificate(
            f"{self._name}_ssl_certificate",
            SSLCertificateProps(
                certificate_secret_name="ssl-certificate-sre-remote-desktop",
                domain_name=props.sre_fqdn,
                admin_email_address=props.admin_email_address,
                key_vault_name=key_vault.name,
                networking_resource_group_name=props.networking_resource_group_name,
                subscription_name=props.subscription_name,
            ),
            opts=child_opts,
        )

        # Register outputs
        self.access_key = Output.secret(storage_account_keys.keys[0].value)
        self.account_name = Output.from_input(storage_account.name)
        self.certificate_secret_id = certificate.secret_id
        self.managed_identity = key_vault_reader
        self.resource_group_name = resource_group.name
        self.sre_fqdn = Output.from_input(props.sre_fqdn)
