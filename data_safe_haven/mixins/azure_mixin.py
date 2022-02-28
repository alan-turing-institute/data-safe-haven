"""Mixin class for anything Azure-aware"""
from data_safe_haven.exceptions import (
    DataSafeHavenAzureException,
    DataSafeHavenInputException,
)
from azure.core.exceptions import ClientAuthenticationError
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import SubscriptionClient


class AzureMixin:
    """Mixin class for anything Azure-aware"""

    def __init__(self, subscription_name, *args, **kwargs):
        self.subscription_name = subscription_name
        self.credential_ = None
        self.subscription_id_ = None
        self.tenant_id_ = None
        super().__init__(*args, **kwargs)

    @property
    def credential(self):
        if not self.credential_:
            self.credential_ = DefaultAzureCredential()
        return self.credential_

    @property
    def subscription_id(self):
        if not self.subscription_id_:
            self.login()
        return self.subscription_id_

    @property
    def tenant_id(self):
        if not self.tenant_id_:
            self.login()
        return self.tenant_id_

    def login(self):
        """Get subscription and tenant IDs"""
        # Connect to Azure clients
        subscription_client = SubscriptionClient(self.credential)

        # Check that the Azure credentials are valid
        try:
            for subscription in subscription_client.subscriptions.list():
                if subscription.display_name == self.subscription_name:
                    self.subscription_id_ = subscription.subscription_id
                    self.tenant_id_ = subscription.tenant_id
                    break
        except ClientAuthenticationError as exc:
            raise DataSafeHavenAzureException(
                "Failed to authenticate with Azure"
            ) from exc
        if not (self.subscription_id and self.tenant_id):
            raise DataSafeHavenInputException(
                f"Could not find subscription '{self.subscription_name}'"
            )
