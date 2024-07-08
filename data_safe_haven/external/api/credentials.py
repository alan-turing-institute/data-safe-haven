"""Classes related to Azure credentials"""

import pathlib
from abc import abstractmethod
from collections.abc import Sequence
from datetime import UTC, datetime
from typing import Any

import jwt
from azure.core.credentials import AccessToken, TokenCredential
from azure.identity import (
    AuthenticationRecord,
    AzureCliCredential,
    CredentialUnavailableError,
    DeviceCodeCredential,
    TokenCachePersistenceOptions,
)

from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.logging import get_logger


class DeferredCredential(TokenCredential):
    """A token credential that wraps and caches other credential classes."""

    token_: AccessToken | None = None

    def __init__(
        self,
        scopes: Sequence[str],
        tenant_id: str | None = None,
    ) -> None:
        self.logger = get_logger()
        self.scopes = scopes
        self.tenant_id = tenant_id

    @property
    def token(self) -> str:
        """Get a token from the credential provider."""
        return str(self.get_token(*self.scopes, tenant_id=self.tenant_id).token)

    @abstractmethod
    def get_credential(self) -> TokenCredential:
        """Get a credential provider from the child class."""
        pass

    def get_token(
        self,
        *scopes: str,
        **kwargs: Any,
    ) -> AccessToken:
        # Require at least 10 minutes of remaining validity
        validity_cutoff = datetime.now(tz=UTC).timestamp() + 10 * 60
        if not DeferredCredential.token_ or (
            DeferredCredential.token_.expires_on < validity_cutoff
        ):
            # Generate a new token and store it at class-level token
            DeferredCredential.token_ = self.get_credential().get_token(
                *scopes, **kwargs
            )
        return DeferredCredential.token_


class AzureApiCredential(DeferredCredential):
    """
    Credential loader used by AzureApi

    Uses AzureCliCredential for authentication
    """

    def __init__(self, scope: str = "https://management.azure.com/.default") -> None:
        super().__init__(scopes=[scope])

    def get_credential(self) -> TokenCredential:
        """Get a new AzureCliCredential."""
        credential = AzureCliCredential(additionally_allowed_tenants=["*"])
        # Check that we are logged into Azure
        try:
            token = credential.get_token(*self.scopes).token
            decoded = jwt.decode(
                token, algorithms=["RS256"], options={"verify_signature": False}
            )
            self.logger.info(
                "You are currently logged into the [blue]Azure CLI[/] with the following details:"
            )
            self.logger.info(
                f"... user: [green]{decoded['name']}[/] ({decoded['oid']})"
            )
            self.logger.info(
                f"... tenant: [green]{decoded['upn'].split('@')[1]}[/] ({decoded['tid']})"
            )
        except CredentialUnavailableError as exc:
            self.logger.error(
                "Please authenticate with Azure: run '[green]az login[/]' using [bold]infrastructure administrator[/] credentials."
            )
            msg = "Error getting account information from Azure CLI."
            raise DataSafeHavenAzureError(msg) from exc
        return credential


class GraphApiCredential(DeferredCredential):
    """
    Credential loader used by GraphApi

    Uses DeviceCodeCredential for authentication
    """

    def __init__(
        self,
        tenant_id: str,
        scopes: Sequence[str] = [],
    ) -> None:
        super().__init__(scopes=scopes, tenant_id=tenant_id)

    def get_credential(self) -> TokenCredential:
        """Get a new DeviceCodeCredential, using cached credentials if they are available"""
        cache_name = f"dsh-{self.tenant_id}"
        authentication_record_path = (
            pathlib.Path.home() / f".msal-authentication-cache-{cache_name}"
        )

        # Read an existing authentication record, using default arguments if unavailable
        kwargs = {}
        try:
            with open(authentication_record_path) as f_auth:
                existing_auth_record = AuthenticationRecord.deserialize(f_auth.read())
                kwargs["authentication_record"] = existing_auth_record
        except FileNotFoundError:
            kwargs["authority"] = "https://login.microsoftonline.com/"
            # Use the Microsoft Graph Command Line Tools client ID
            kwargs["client_id"] = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
            kwargs["tenant_id"] = self.tenant_id

        # Get a credential with a custom callback
        def callback(verification_uri: str, user_code: str, _: datetime) -> None:
            self.logger.info(
                f"Go to [bold]{verification_uri}[/] in a web browser and enter the code [bold]{user_code}[/] at the prompt."
            )
            self.logger.info(
                "Use [bold]global administrator credentials[/] for your [blue]Entra ID directory[/] to sign-in."
            )

        credential = DeviceCodeCredential(
            cache_persistence_options=TokenCachePersistenceOptions(name=cache_name),
            prompt_callback=callback,
            **kwargs,
        )

        # Write out an authentication record for this credential
        new_auth_record = credential.authenticate(scopes=self.scopes)
        with open(authentication_record_path, "w") as f_auth:
            f_auth.write(new_auth_record.serialize())

        # Write confirmation details about this login
        self.logger.info(
            "You are currently logged into the [blue]Microsoft Graph API[/] with the following details:"
        )
        self.logger.info(
            f"... user: [green]{new_auth_record.username}[/] ({new_auth_record._home_account_id.split('.')[0]})"
        )
        self.logger.info(
            f"... tenant: [green]{new_auth_record._username.split('@')[1]}[/] ({new_auth_record._tenant_id})"
        )

        # Return the credential
        return credential
