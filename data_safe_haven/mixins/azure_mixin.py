"""Mixin class for anything Azure-aware"""
# Standard library imports
from typing import cast, Optional

# Third party imports
from azure.core.exceptions import ClientAuthenticationError
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import SubscriptionClient
from azure.mgmt.resource.subscriptions.models import Subscription

# Local imports
from data_safe_haven.exceptions import (
    DataSafeHavenAzureException,
    DataSafeHavenInputException,
)


class AzureMixin:
    """Mixin class for anything Azure-aware"""

    def __init__(self, subscription_name, *args, **kwargs):
        self.subscription_name: str = subscription_name
        self.credential_: Optional[DefaultAzureCredential] = None
        self.subscription_id_: Optional[str] = None
        self.tenant_id_: Optional[str] = None
        super().__init__(*args, **kwargs)

    @property
    def credential(self):
        if not self.credential_:
            self.credential_ = DefaultAzureCredential(
                exclude_interactive_browser_credential=False,
                exclude_shared_token_cache_credential=True,  # this requires multiple approvals per sign-in
                exclude_visual_studio_code_credential=True,  # this often fails
            )
        return self.credential_

    @property
    def subscription_id(self) -> str:
        if not self.subscription_id_:
            self.login()
        if not self.subscription_id_:
            raise DataSafeHavenAzureException("Failed to load subscription ID.")
        return self.subscription_id_

    @property
    def tenant_id(self) -> str:
        if not self.tenant_id_:
            self.login()
        if not self.tenant_id_:
            raise DataSafeHavenAzureException("Failed to load tenant ID.")
        return self.tenant_id_

    def login(self):
        """Get subscription and tenant IDs"""
        # Connect to Azure clients
        subscription_client = SubscriptionClient(self.credential)

        # Check that the Azure credentials are valid
        try:
            for subscription in [
                cast(Subscription, s) for s in subscription_client.subscriptions.list()
            ]:
                if subscription.display_name == self.subscription_name:
                    self.subscription_id_ = subscription.subscription_id
                    self.tenant_id_ = subscription.tenant_id
                    break
        except ClientAuthenticationError as exc:
            raise DataSafeHavenAzureException(
                f"Failed to authenticate with Azure.\n{str(exc)}"
            ) from exc
        if not (self.subscription_id and self.tenant_id):
            raise DataSafeHavenInputException(
                f"Could not find subscription '{self.subscription_name}'"
            )
