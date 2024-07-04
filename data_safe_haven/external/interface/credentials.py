"""Classes related to Azure credentials"""

import pathlib
from abc import ABCMeta, abstractmethod
from collections.abc import Sequence
from datetime import datetime

from azure.core.credentials import TokenCredential
from azure.identity import (
    AuthenticationRecord,
    AzureCliCredential,
    DeviceCodeCredential,
    TokenCachePersistenceOptions,
)

from data_safe_haven.external.api.azure_cli import AzureCliSingleton
from data_safe_haven.logging import get_logger


class DeferredCredentialLoader(metaclass=ABCMeta):
    """A wrapper class that initialises and caches credentials as they are needed"""

    def __init__(
        self,
        scopes: Sequence[str],
        tenant_id: str | None = None,
    ) -> None:
        self.credential_: TokenCredential | None = None
        self.scopes = scopes
        self.tenant_id = tenant_id

    @property
    def credential(self) -> TokenCredential:
        """Return the cached credential provider."""
        if not self.credential_:
            self.credential_ = self.get_credential()
        return self.credential_

    @property
    def token(self) -> str:
        """Get a token from the credential provider."""
        return str(
            self.credential.get_token(
                *self.scopes,
                tenant_id=self.tenant_id,
            ).token
        )

    @abstractmethod
    def get_credential(self) -> TokenCredential:
        """Get new credential provider."""
        pass


class AzureApiCredentialLoader(DeferredCredentialLoader):
    """
    Credential loader used by AzureApi

    Uses AzureCliCredential for authentication
    """

    def __init__(self) -> None:
        super().__init__(scopes=["https://management.azure.com/.default"])

    def get_credential(self) -> TokenCredential:
        """Get a new AzureCliCredential."""
        AzureCliSingleton().confirm()  # get user confirmation of the current account
        return AzureCliCredential(additionally_allowed_tenants=["*"])


class GraphApiCredentialLoader(DeferredCredentialLoader):
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
        self.logger = get_logger()

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
