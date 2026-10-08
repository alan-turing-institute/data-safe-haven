"""Revoke one ingress rule without rewriting unrelated storage account access."""

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from azure.core.exceptions import HttpResponseError
from azure.mgmt.storage.models import (
    IPRule,
    NetworkRuleSet,
    StorageAccountUpdateParameters,
)

from data_safe_haven.exceptions import DataSafeHavenAzureStorageError
from data_safe_haven.external.api.azure_sdk import AzureSdk


@pytest.fixture
def setup_sdk(mocker):
    sdk = AzureSdk(subscription_name="test-subscription")
    sdk.subscription_id_ = "subscription-id"
    mocker.patch.object(sdk, "credential", return_value=MagicMock())
    client = mocker.patch(
        "data_safe_haven.external.api.azure_sdk.StorageManagementClient"
    )
    account = client.return_value.storage_accounts
    access = NetworkRuleSet(
        default_action="Deny",
        bypass="AzureServices",
        ip_rules=[
            IPRule(ip_address_or_range="198.51.100.10", action="Allow"),
            IPRule(ip_address_or_range="203.0.113.0/28", action="Allow"),
            IPRule(ip_address_or_range="198.51.100.20", action="Allow"),
        ],
        virtual_network_rules=[],
    )
    account.get_properties.return_value = SimpleNamespace(network_rule_set=access)
    return sdk, account, access


def test_remove_only_requested_exact_rule_and_preserve_other_firewall_settings(
    setup_sdk,
):
    sdk, account, _ = setup_sdk
    assert sdk.remove_storage_account_ip_rule("rg", "storage", "198.51.100.10/32")
    account.get_properties.assert_called_once_with("rg", "storage")
    account.update.assert_called_once()
    call = account.update.call_args
    assert call.args[:2] == ("rg", "storage")
    assert isinstance(call.args[2], StorageAccountUpdateParameters)
    actual = call.args[2].network_rule_set
    assert actual.default_action == "Deny"
    assert actual.bypass == "AzureServices"
    assert actual.virtual_network_rules == []
    assert [r.ip_address_or_range for r in actual.ip_rules] == [
        "203.0.113.0/28",
        "198.51.100.20",
    ]


def test_absent_rule_is_idempotent_and_does_not_patch_account(setup_sdk):
    sdk, account, access = setup_sdk
    assert not sdk.remove_storage_account_ip_rule("rg", "storage", "192.0.2.6")
    account.update.assert_not_called()
    assert len(access.ip_rules) == 3


def test_only_exact_cidr_is_removed_not_an_overlapping_subnet(setup_sdk):
    sdk, account, access = setup_sdk
    assert not sdk.remove_storage_account_ip_rule("rg", "storage", "203.0.113.4")
    account.update.assert_not_called()
    assert sdk.remove_storage_account_ip_rule("rg", "storage", "203.0.113.0/28")
    assert [r.ip_address_or_range for r in access.ip_rules] == [
        "198.51.100.10",
        "198.51.100.20",
    ]


def test_network_rules_unavailable_fails_closed(setup_sdk):
    sdk, account, _ = setup_sdk
    account.get_properties.return_value = SimpleNamespace(network_rule_set=None)
    with pytest.raises(DataSafeHavenAzureStorageError, match="no firewall"):
        sdk.remove_storage_account_ip_rule("rg", "storage", "192.0.2.3")
    account.update.assert_not_called()


def test_update_failure_is_reported(setup_sdk):
    sdk, account, _ = setup_sdk
    account.update.side_effect = HttpResponseError(message="throttled")
    with pytest.raises(
        DataSafeHavenAzureStorageError, match="Could not update firewall"
    ):
        sdk.remove_storage_account_ip_rule("rg", "storage", "198.51.100.10")


def test_invalid_address_fails_before_contacting_azure(setup_sdk):
    sdk, account, _ = setup_sdk
    with pytest.raises(ValueError):
        sdk.remove_storage_account_ip_rule("rg", "storage", "not-an-address")
    account.get_properties.assert_not_called()
