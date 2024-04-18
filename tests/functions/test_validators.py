import pytest

from data_safe_haven.functions.validators import (
    validate_aad_guid,
    validate_fqdn,
    validate_unique_list,
)
from data_safe_haven.utility.enums import DatabaseSystem


class TestValidateAadGuid:
    @pytest.mark.parametrize(
        "guid",
        [
            "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            "10de18e7-b238-6f1e-a4ad-772708929203",
        ],
    )
    def test_validate_aad_guid(self, guid):
        assert validate_aad_guid(guid) == guid

    @pytest.mark.parametrize(
        "guid",
        [
            "10de18e7_b238_6f1e_a4ad_772708929203",
            "not a guid",
        ],
    )
    def test_validate_aad_guid_fail(self, guid):
        with pytest.raises(ValueError, match="Expected GUID"):
            validate_aad_guid(guid)


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
    def test_validate_fqdn(self, fqdn):
        assert validate_fqdn(fqdn) == fqdn

    @pytest.mark.parametrize(
        "fqdn",
        [
            "invalid",
            "%example.com",
            "a b c.com",
            "a_b_c.com",
        ],
    )
    def test_validate_fqdn_fail(self, fqdn):
        with pytest.raises(
            ValueError, match="Expected valid fully qualified domain name"
        ):
            validate_fqdn(fqdn)


class MyClass:
    def __init__(self, x):
        self.x = x

    def __eq__(self, other):
        return self.x == other.x

    def __hash__(self):
        return hash(self.x)


class TestValidateUniqueList:
    @pytest.mark.parametrize(
        "items",
        [
            [1, 2, 3],
            ["a", 5, len],
            [MyClass(x=1), MyClass(x=2)],
        ],
    )
    def test_validate_unique_list(self, items):
        validate_unique_list(items)

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
    def test_validate_unique_list_fail(self, items):
        with pytest.raises(ValueError, match="All items must be unique."):
            validate_unique_list(items)
