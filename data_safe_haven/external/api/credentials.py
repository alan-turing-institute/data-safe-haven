"""Classes related to Azure credentials"""

from abc import abstractmethod
from collections.abc import Sequence
from datetime import UTC, datetime
from typing import Any, ClassVar

import jwt
from azure.core.credentials import AccessToken, TokenCredential
from azure.core.exceptions import ClientAuthenticationError
from azure.identity import (
    AuthenticationRecord,
    AzureCliCredential,
    CredentialUnavailableError,
    DeviceCodeCredential,
    TokenCachePersistenceOptions,
)

from data_safe_haven import console
from data_safe_haven.directories import config_dir
from data_safe_haven.exceptions import (
    DataSafeHavenAzureError,
    DataSafeHavenCachedCredentialError,
    DataSafeHavenValueError,
)
from data_safe_haven.logging import get_logger
from data_safe_haven.types import AzureSdkCredentialScope


class DeferredCredential(TokenCredential):
    """A token credential that wraps and caches other credential classes."""

    tokens_: ClassVar[dict[str, AccessToken]] = {}
    cache_: ClassVar[set[tuple[str, str]]] = set()
    name: ClassVar[str] = "Credential name"

    def __init__(
        self,
        *,
        scopes: Sequence[str],
        skip_confirmation: bool,
        tenant_id: str | None = None,
    ) -> None:
        self.skip_confirmation = skip_confirmation
        self.logger = get_logger()
        self.scopes = scopes
        self.tenant_id = tenant_id

    @property
    def token(self) -> str:
        """Get a token from the credential provider."""
        return str(self.get_token(*self.scopes, tenant_id=self.tenant_id).token)

    @classmethod
    def decode_token(cls, auth_token: str) -> dict[str, Any]:
        try:
            return dict(
                jwt.decode(
                    auth_token,
                    algorithms=["RS256"],
                    options={"verify_signature": False},
                )
            )
        except (jwt.exceptions.DecodeError, KeyError) as exc:
            msg = "Could not interpret input as an Azure authentication token."
            raise DataSafeHavenValueError(msg) from exc

    @abstractmethod
    def get_credential(self) -> TokenCredential:
        """Get a credential provider from the child class."""

    def confirm_credentials_interactive(
        self,
        user_name: str,
        user_id: str,
        tenant_name: str,
        tenant_id: str,
    ) -> bool:
        """
        Allow user to confirm that credentials are correct.

        Responses are cached so the user will only be prompted once per run.
        If 'skip_confirmation' is set, then no confirmation will be performed.
        """
        if self.skip_confirmation:
            return True
        if (user_id, tenant_id) in DeferredCredential.cache_:
            return True

        DeferredCredential.cache_.add((user_id, tenant_id))
        self.logger.info(f"You are logged into the [blue]{self.name}[/] as:")
        self.logger.info(f"\tuser: [green]{user_name}[/] ({user_id})")
        self.logger.info(f"\ttenant: [green]{tenant_name}[/] ({tenant_id})")

        return console.confirm("Are these details correct?", default_to_yes=True)

    def get_token(
        self,
        *scopes: str,
        **kwargs: Any,
    ) -> AccessToken:
        combined_scopes = " ".join(scopes)
        # Require at least 10 minutes of remaining validity
        # The 'expires_on' property is a Unix timestamp integer in seconds
        validity_cutoff = datetime.now(tz=UTC).timestamp() + 10 * 60
        if not DeferredCredential.tokens_.get(combined_scopes, None) or (
            DeferredCredential.tokens_[combined_scopes].expires_on < validity_cutoff
        ):
            # Generate a new token and store it at class-level token
            DeferredCredential.tokens_[combined_scopes] = (
                self.get_credential().get_token(*scopes, **kwargs)
            )
        return DeferredCredential.tokens_[combined_scopes]


class AzureSdkCredential(DeferredCredential):
    """
    Credential loader used by AzureSdk

    Uses AzureCliCredential for authentication
    """

    name: ClassVar[str] = "Azure CLI"

    def __init__(
        self,
        scope: AzureSdkCredentialScope = AzureSdkCredentialScope.DEFAULT,
        *,
        skip_confirmation: bool = False,
    ) -> None:
        super().__init__(scopes=[scope.value], skip_confirmation=skip_confirmation)

    def get_credential(self) -> TokenCredential:
        """Get a new AzureCliCredential."""
        credential = AzureCliCredential(additionally_allowed_tenants=["*"])
        # Confirm that these are the desired credentials
        try:
            decoded = self.decode_token(credential.get_token(*self.scopes).token)
        except (CredentialUnavailableError, DataSafeHavenValueError) as exc:
            msg = "Error getting account information from Azure CLI."
            raise DataSafeHavenAzureError(msg) from exc

        if not self.confirm_credentials_interactive(
            user_name=decoded["name"],
            user_id=decoded["oid"],
            tenant_name=decoded["upn"].split("@")[1],
            tenant_id=decoded["tid"],
        ):
            self.logger.error(
                "Please authenticate with Azure: run '[green]az login[/]' using [bold]infrastructure administrator[/] credentials."
            )
            msg = "Selected credentials are incorrect."
            raise DataSafeHavenCachedCredentialError(msg)

        return credential


class GraphApiCredential(DeferredCredential):
    """
    Credential loader used by GraphApi

    Uses DeviceCodeCredential for authentication
    """

    name: ClassVar[str] = "Microsoft Graph API"

    def __init__(
        self,
        tenant_id: str,
        *,
        scopes: Sequence[str] = [],
        skip_confirmation: bool = False,
    ) -> None:
        super().__init__(
            scopes=scopes, tenant_id=tenant_id, skip_confirmation=skip_confirmation
        )

    def get_credential(self) -> TokenCredential:
        """Get a new DeviceCodeCredential, using cached credentials if they are available"""
        cache_name = f"dsh-{self.tenant_id}"
        authentication_record_path = (
            config_dir() / f".msal-authentication-cache-{cache_name}"
        )

        # Read an existing authentication record, using default arguments if unavailable
        kwargs = {}
        if authentication_record_path.is_file():
            with open(authentication_record_path) as f_auth:
                existing_auth_record = AuthenticationRecord.deserialize(f_auth.read())
                kwargs["authentication_record"] = existing_auth_record
        else:
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
            cache_persistence_options=TokenCachePersistenceOptions(
                name=cache_name, allow_unencrypted_storage=True
            ),
            prompt_callback=callback,
            **kwargs,
        )

        # Attempt to authenticate, writing out the record if successful
        try:
            new_auth_record = credential.authenticate(scopes=self.scopes)
            with open(authentication_record_path, "w") as f_auth:
                f_auth.write(new_auth_record.serialize())
        except ClientAuthenticationError as exc:
            self.logger.error(exc.message)
            msg = "Error getting account information from Microsoft Graph API."
            raise DataSafeHavenAzureError(msg) from exc

        # Confirm that these are the desired credentials
        if not self.confirm_credentials_interactive(
            user_name=new_auth_record.username,
            user_id=new_auth_record._home_account_id.split(".")[0],
            tenant_name=new_auth_record._username.split("@")[1],
            tenant_id=new_auth_record._tenant_id,
        ):
            self.logger.error(
                f"Delete the cached credential file [green]{authentication_record_path}[/] and rerun dsh to authenticate with {self.name}"
            )
            msg = "Selected credentials are incorrect."
            raise DataSafeHavenCachedCredentialError(msg)

        # Return the credential
        return credential
