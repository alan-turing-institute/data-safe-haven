"""Pulumi dynamic component for SSL certificates uploaded to an Azure KeyVault."""
from contextlib import suppress
from typing import Any

from acme.errors import ValidationError
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPrivateKey
from cryptography.hazmat.primitives.serialization import (
    NoEncryption,
    load_pem_private_key,
    pkcs12,
)
from cryptography.x509 import load_pem_x509_certificate
from pulumi import Input, Output, ResourceOptions
from pulumi.dynamic import CreateResult, DiffResult, Resource
from simple_acme_dns import ACMEClient

from data_safe_haven.exceptions import DataSafeHavenSSLError
from data_safe_haven.external import AzureApi

from .dsh_resource_provider import DshResourceProvider


class SSLCertificateProps:
    """Props for the SSLCertificate class"""

    def __init__(
        self,
        certificate_secret_name: Input[str],
        domain_name: Input[str],
        admin_email_address: Input[str],
        key_vault_name: Input[str],
        networking_resource_group_name: Input[str],
        subscription_name: Input[str],
    ) -> None:
        self.certificate_secret_name = certificate_secret_name
        self.domain_name = domain_name
        self.admin_email_address = admin_email_address
        self.key_vault_name = key_vault_name
        self.networking_resource_group_name = networking_resource_group_name
        self.subscription_name = subscription_name


class SSLCertificateProvider(DshResourceProvider):
    @staticmethod
    def refresh(props: dict[str, Any]) -> dict[str, Any]:
        outs = dict(**props)
        with suppress(Exception):
            azure_api = AzureApi(outs["subscription_name"], disable_logging=True)
            certificate = azure_api.get_keyvault_certificate(
                outs["certificate_secret_name"], outs["key_vault_name"]
            )
            if certificate.secret_id:
                outs["secret_id"] = certificate.secret_id
        return outs

    def create(self, props: dict[str, Any]) -> CreateResult:
        """Create new SSL certificate."""
        outs = dict(**props)
        try:
            # Note that we must set the key to RSA-2048 before generating the CSR
            # The default is ecdsa-with-SHA25, which Azure Key Vault cannot read
            client = ACMEClient(
                domains=[props["domain_name"]],
                email=props["admin_email_address"],
                directory="https://acme-v02.api.letsencrypt.org/directory",
                nameservers=["8.8.8.8", "1.1.1.1"],
                new_account=True,
            )
            # Generate private key and CSR
            private_key_bytes = client.generate_private_key(key_type="rsa2048")
            client.generate_csr()
            # Request DNS verification tokens and add them to the DNS record
            azure_api = AzureApi(props["subscription_name"], disable_logging=True)
            for token in client.request_verification_tokens():
                azure_api.ensure_dns_txt_record(
                    record_name=token[0].replace(f".{props['domain_name']}", ""),
                    record_value=token[1],
                    resource_group_name=props["networking_resource_group_name"],
                    zone_name=props["domain_name"],
                )
            # Wait for DNS propagation to complete
            if not client.check_dns_propagation(
                authoritative=False, round_robin=True, verbose=False
            ):
                msg = "DNS propagation failed"
                raise DataSafeHavenSSLError(msg)
            # Request a signed certificate
            try:
                certificate_bytes = client.request_certificate()
            except ValidationError as exc:
                raise DataSafeHavenSSLError(
                    "ACME validation error:\n"
                    + "\n".join([str(auth_error) for auth_error in exc.failed_authzrs])
                ) from exc
            # Although KeyVault will accept a PEM certificate (where we simply
            # prepend the private key) we need a PFX certificate for
            # compatibility with ApplicationGateway
            private_key = load_pem_private_key(private_key_bytes, None)
            if not isinstance(private_key, RSAPrivateKey):
                msg = f"Private key is of type {type(private_key)} not RSAPrivateKey."
                raise TypeError(msg)
            all_certs = [
                load_pem_x509_certificate(data)
                for data in certificate_bytes.split(b"\n\n")
            ]
            certificate = next(
                cert for cert in all_certs if props["domain_name"] in str(cert.subject)
            )
            ca_certs = [cert for cert in all_certs if cert != certificate]
            pfx_bytes = pkcs12.serialize_key_and_certificates(
                props["certificate_secret_name"].encode("utf-8"),
                private_key,
                certificate,
                ca_certs,
                NoEncryption(),
            )
            # Add certificate to KeyVault
            kvcert = azure_api.import_keyvault_certificate(
                certificate_name=props["certificate_secret_name"],
                certificate_contents=pfx_bytes,
                key_vault_name=props["key_vault_name"],
            )
            outs["secret_id"] = kvcert.secret_id
        except Exception as exc:
            msg = (
                f"Failed to create SSL certificate [green]{props['certificate_secret_name']}[/]"
                f" for [green]{props['domain_name']}[/].\n{exc}"
            )
            raise DataSafeHavenSSLError(msg) from exc
        return CreateResult(
            f"SSLCertificate-{props['certificate_secret_name']}",
            outs=outs,
        )

    def delete(self, id_: str, props: dict[str, Any]) -> None:
        """Delete an SSL certificate."""
        # Use `id` as a no-op to avoid ARG002 while maintaining function signature
        id(id_)
        try:
            # Remove the DNS record
            azure_api = AzureApi(props["subscription_name"], disable_logging=True)
            azure_api.remove_dns_txt_record(
                record_name="_acme_challenge",
                resource_group_name=props["networking_resource_group_name"],
                zone_name=props["domain_name"],
            )
            # Remove the Key Vault certificate
            azure_api.remove_keyvault_certificate(
                certificate_name=props["certificate_secret_name"],
                key_vault_name=props["key_vault_name"],
            )
        except Exception as exc:
            msg = (
                f"Failed to delete SSL certificate [green]{props['certificate_secret_name']}[/]"
                f" for [green]{props['domain_name']}[/].\n{exc}"
            )
            raise DataSafeHavenSSLError(msg) from exc

    def diff(
        self,
        id_: str,
        old_props: dict[str, Any],
        new_props: dict[str, Any],
    ) -> DiffResult:
        """Calculate diff between old and new state"""
        # Use `id` as a no-op to avoid ARG002 while maintaining function signature
        id(id_)
        return self.partial_diff(old_props, new_props, [])


class SSLCertificate(Resource):
    _resource_type_name = "dsh:common:SSLCertificate"  # set resource type
    secret_id: Output[str]

    def __init__(
        self,
        name: str,
        props: SSLCertificateProps,
        opts: ResourceOptions | None = None,
    ):
        super().__init__(
            SSLCertificateProvider(),
            name,
            {"secret_id": None, **vars(props)},
            opts,
        )
