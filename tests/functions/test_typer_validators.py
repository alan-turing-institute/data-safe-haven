import pytest
from typer import BadParameter

from data_safe_haven.functions.typer_validators import typer_validate_aad_guid


class TestTyperValidateAadGuid:
    @pytest.mark.parametrize(
        "guid",
        [
            "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            "10de18e7-b238-6f1e-a4ad-772708929203",
        ],
    )
    def test_typer_validate_aad_guid(self, guid):
        assert typer_validate_aad_guid(guid) == guid

    @pytest.mark.parametrize(
        "guid",
        [
            "10de18e7_b238_6f1e_a4ad_772708929203",
            "not a guid",
        ],
    )
    def test_typer_validate_aad_guid_fail(self, guid):
        with pytest.raises(BadParameter, match="Expected GUID"):
            typer_validate_aad_guid(guid)

    def test_typer_validate_aad_guid_nonae(self):
        assert typer_validate_aad_guid(None) is None
