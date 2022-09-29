# Third party imports
from pulumi import ComponentResource, Input, ResourceOptions, Output
from pulumi_azure_native import keyvault, managedidentity

# Local imports
from ..dynamic.ssl_certificate import SSLCertificateProps, SSLCertificate


class SREKeyVaultProps:
    """Properties for SREKeyVaultComponent"""

    def __init__(
        self,
        admin_group_id: Input[str],
        key_vault_resource_group_name: Input[str],
        location: Input[str],
        networking_resource_group_name: Input[str],
        subscription_name: Input[str],
        sre_fqdn: Input[str],
        sre_name: Input[str],
        tenant_id: Input[str],
    ):
        self.admin_group_id = admin_group_id
        self.key_vault_resource_group_name = key_vault_resource_group_name
        self.location = location
        self.networking_resource_group_name = networking_resource_group_name
        self.subscription_name = subscription_name
        self.sre_fqdn = sre_fqdn
        self.sre_name = sre_name
        self.tenant_id = tenant_id


class SREKeyVaultComponent(ComponentResource):
    """Deploy SRE secrets with Pulumi"""

    def __init__(
        self, name: str, props: SREKeyVaultProps, opts: ResourceOptions = None
    ):
        super().__init__("dsh:sre:SREKeyVaultComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        # Define Key Vault reader
        sre_key_vault_reader = managedidentity.UserAssignedIdentity(
            "sre_key_vault_reader",
            location=props.location,
            resource_group_name=props.key_vault_resource_group_name,
            resource_name_=f"sre-{props.sre_name}-key-vault-reader",
        )

        # Define SRE KeyVault
        vault = keyvault.Vault(
            "vault",
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
                        object_id=sre_key_vault_reader.client_id,
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
            resource_group_name=props.key_vault_resource_group_name,
            vault_name=f"kv-sre-{props.sre_name[:9]}-secrets",  # maximum of 24 characters
        )

        # Define SSL certificate for this FQDN
        certificate = SSLCertificate(
            "ssl_certificate",
            SSLCertificateProps(
                certificate_secret_name="ssl-certificate-fqdn",
                domain_name=props.sre_fqdn,
                key_vault_name=vault.name,
                networking_resource_group_name=props.networking_resource_group_name,
                subscription_name=props.subscription_name,
            ),
        )

        # Register outputs
        self.certificate_secret_id = certificate.secret_id
        self.managed_identity = sre_key_vault_reader
        self.resource_group_name = Output.from_input(
            props.key_vault_resource_group_name
        )
        self.sre_fqdn = Output.from_input(props.sre_fqdn)
