"""Standalone utility class for anything that needs to authenticate against Azure"""

from typing import cast

from azure.core.exceptions import ClientAuthenticationError
from azure.identity import AzureCliCredential
from azure.mgmt.resource.subscriptions import SubscriptionClient
from azure.mgmt.resource.subscriptions.models import Subscription

from data_safe_haven.exceptions import (
    DataSafeHavenAzureAPIAuthenticationError,
    DataSafeHavenAzureError,
    DataSafeHavenInputError,
)


class AzureAuthenticator:
    """Standalone utility class for anything that needs to authenticate against Azure"""

    def __init__(self, subscription_name: str) -> None:
        self.subscription_name: str = subscription_name
        self.credential_: AzureCliCredential | None = None
        self.subscription_id_: str | None = None
        self.tenant_id_: str | None = None

    @property
    def credential(self) -> AzureCliCredential:
        if not self.credential_:
            self.credential_ = AzureCliCredential(
                additionally_allowed_tenants=["*"],
            )
        return self.credential_

    @property
    def subscription_id(self) -> str:
        if not self.subscription_id_:
            self.login()
        if not self.subscription_id_:
            msg = "Failed to load subscription ID."
            raise DataSafeHavenAzureError(msg)
        return self.subscription_id_

    @property
    def tenant_id(self) -> str:
        if not self.tenant_id_:
            self.login()
        if not self.tenant_id_:
            msg = "Failed to load tenant ID."
            raise DataSafeHavenAzureError(msg)
        return self.tenant_id_

    def login(self) -> None:
        """Get subscription and tenant IDs"""
        # Connect to Azure clients
        subscription_client = SubscriptionClient(self.credential)

        # Check that the Azure credentials are valid
        try:
            for subscription in cast(
                list[Subscription], subscription_client.subscriptions.list()
            ):
                if subscription.display_name == self.subscription_name:
                    self.subscription_id_ = subscription.subscription_id
                    self.tenant_id_ = subscription.tenant_id
                    break
        except ClientAuthenticationError as exc:
            msg = f"Failed to authenticate with Azure API.\n{exc}"
            raise DataSafeHavenAzureAPIAuthenticationError(msg) from exc
        if not (self.subscription_id and self.tenant_id):
            msg = f"Could not find subscription '{self.subscription_name}'"
            raise DataSafeHavenInputError(msg)
