import pytest

from data_safe_haven import validators
from data_safe_haven.types import DatabaseSystem


class TestValidateAadGuid:
    @pytest.mark.parametrize(
        "guid",
        [
            "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            "10de18e7-b238-6f1e-a4ad-772708929203",
        ],
    )
    def test_aad_guid(self, guid):
        assert validators.aad_guid(guid) == guid

    @pytest.mark.parametrize(
        "guid",
        [
            "10de18e7_b238_6f1e_a4ad_772708929203",
            "not a guid",
        ],
    )
    def test_aad_guid_fail(self, guid):
        with pytest.raises(ValueError, match="Expected GUID"):
            validators.aad_guid(guid)


class TestAzureSubscriptionName:
    @pytest.mark.parametrize(
        "subscription_name",
        [
            "My Subscription",
            "Example-Subscription",
            "Subscription5",
        ],
    )
    def test_subscription_name(self, subscription_name):
        assert (
            validators.azure_subscription_name(subscription_name) == subscription_name
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
        with pytest.raises(ValueError, match="can only contain alphanumeric"):
            validators.azure_subscription_name(subscription_name)


class TestValidateFqdn:
    @pytest.mark.parametrize(
        "fqdn",
        [
            "shm.acme.com",
            "example.com",
            "a.b.c.com.",
            "a-b-c.com",
        ],
    )
    def test_fqdn(self, fqdn):
        assert validators.fqdn(fqdn) == fqdn

    @pytest.mark.parametrize(
        "fqdn",
        [
            "invalid",
            "%example.com",
            "a b c.com",
            "a_b_c.com",
        ],
    )
    def test_fqdn_fail(self, fqdn):
        with pytest.raises(
            ValueError, match="Expected valid fully qualified domain name"
        ):
            validators.fqdn(fqdn)


class TestValidateIpAddress:
    @pytest.mark.parametrize(
        "ip_address,output",
        [
            ("127.0.0.1", "127.0.0.1/32"),
            ("0.0.0.0/0", "0.0.0.0/0"),
            ("192.168.171.1/32", "192.168.171.1/32"),
        ],
    )
    def test_ip_address(self, ip_address, output):
        assert validators.ip_address(ip_address) == output

    @pytest.mark.parametrize(
        "ip_address",
        [
            "example.com",
            "University of Life",
            "999.999.999.999",
            "0.0.0.0/-1",
            "255.255.255.0/2",
        ],
    )
    def test_ip_address_fail(self, ip_address):
        with pytest.raises(
            ValueError,
            match="Expected valid IPv4 address, for example '1.1.1.1'.",
        ):
            validators.ip_address(ip_address)


class TestValidateSafeString:
    @pytest.mark.parametrize(
        "safe_string",
        [
            "valid_with_underscores-and-hyphens",
            "mIxeDCAseiNpuT",
            "0123456789",
        ],
    )
    def test_safe_string(self, safe_string):
        assert validators.safe_string(safe_string) == safe_string

    @pytest.mark.parametrize(
        "safe_string",
        [
            "has a space",
            "has!special@characters",
            "has\tnon\rprinting\ncharacters",
            "",
            "🙂",
        ],
    )
    def test_safe_string_fail(self, safe_string):
        with pytest.raises(
            ValueError,
            match="Expected valid string containing only letters, numbers, hyphens and underscores",
        ):
            validators.safe_string(safe_string)


class MyClass:
    def __init__(self, x):
        self.x = x

    def __eq__(self, other):
        return self.x == other.x

    def __hash__(self):
        return hash(self.x)


class TestUniqueList:
    @pytest.mark.parametrize(
        "items",
        [
            [1, 2, 3],
            ["a", 5, len],
            [MyClass(x=1), MyClass(x=2)],
        ],
    )
    def test_unique_list(self, items):
        validators.unique_list(items)

    @pytest.mark.parametrize(
        "items",
        [
            [DatabaseSystem.POSTGRESQL, DatabaseSystem.POSTGRESQL],
            [DatabaseSystem.POSTGRESQL, 2, DatabaseSystem.POSTGRESQL],
            [1, 1],
            ["abc", "abc"],
            [MyClass(x=1), MyClass(x=1)],
        ],
    )
    def test_unique_list_fail(self, items):
        with pytest.raises(ValueError, match="All items must be unique."):
            validators.unique_list(items)
