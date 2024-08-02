import pytest
from typer import BadParameter

from data_safe_haven import validators


class TestTyperAadGuid:
    @pytest.mark.parametrize(
        "guid",
        [
            "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            "10de18e7-b238-6f1e-a4ad-772708929203",
        ],
    )
    def test_typer_aad_guid(self, guid):
        assert validators.typer_aad_guid(guid) == guid

    @pytest.mark.parametrize(
        "guid",
        [
            "10de18e7_b238_6f1e_a4ad_772708929203",
            "not a guid",
        ],
    )
    def test_typer_aad_guid_fail(self, guid):
        with pytest.raises(BadParameter, match="Expected GUID"):
            validators.typer_aad_guid(guid)

    def test_typer_aad_guid_none(self):
        assert validators.typer_aad_guid(None) is None


class TestTyperAzureSubscriptionName:
    @pytest.mark.parametrize(
        "subscription_name",
        [
            "MySubscription",
            "Example-Subscription",
            "Subscription5",
        ],
    )
    def test_typer_subscription_name(self, subscription_name):
        assert (
            validators.typer_azure_subscription_name(subscription_name)
            == subscription_name
        )

    @pytest.mark.parametrize(
        "subscription_name",
        [
            "My!Subscription",
            "",
            "%^*",
            "1@ subscription",
            "sübscríptìőn",
            "🙂",
        ],
    )
    def test_subscription_name_fail(self, subscription_name):
        with pytest.raises(BadParameter, match="can only contain alphanumeric"):
            validators.typer_azure_subscription_name(subscription_name)

    def test_typer_aad_guid_none(self):
        assert validators.typer_azure_subscription_name(None) is None
