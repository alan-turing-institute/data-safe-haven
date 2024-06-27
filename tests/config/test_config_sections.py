import pytest
from pydantic import ValidationError

from data_safe_haven.config.config_sections import (
    ConfigSectionAzure,
    ConfigSectionSHM,
    ConfigSectionSRE,
    ConfigSubsectionRemoteDesktopOpts,
)
from data_safe_haven.types import DatabaseSystem, SoftwarePackageCategory


class TestConfigSectionAzure:
    def test_constructor(self) -> None:
        ConfigSectionAzure(
            location="uksouth",
            subscription_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        )

    def test_invalid_location(self):
        with pytest.raises(
            ValidationError, match="Value error, Expected valid Azure location"
        ):
            ConfigSectionAzure(
                location="not_a_location",
                subscription_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
                tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            )


class TestConfigSectionSHM:
    def test_constructor(self) -> None:
        ConfigSectionSHM(
            admin_group_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            entra_tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            fqdn="shm.acme.com",
        )

    def test_invalid_guid(self, shm_config_section_dict):
        shm_config_section_dict["entra_tenant_id"] = "not a guid"
        with pytest.raises(
            ValidationError, match="Value error, Expected GUID, for example"
        ):
            ConfigSectionSHM(**shm_config_section_dict)


class TestConfigSectionSRE:
    def test_constructor(
        self, remote_desktop_config: ConfigSubsectionRemoteDesktopOpts
    ) -> None:
        sre_config = ConfigSectionSRE(
            admin_email_address="admin@example.com",
            admin_ip_addresses=["1.2.3.4"],
            databases=[DatabaseSystem.POSTGRESQL],
            data_provider_ip_addresses=["2.3.4.5"],
            remote_desktop=remote_desktop_config,
            workspace_skus=["Standard_D2s_v4"],
            research_user_ip_addresses=["3.4.5.6"],
            software_packages=SoftwarePackageCategory.ANY,
            timezone="Australia/Perth",
        )
        assert sre_config.admin_email_address == "admin@example.com"
        assert sre_config.admin_ip_addresses[0] == "1.2.3.4/32"
        assert sre_config.databases[0] == DatabaseSystem.POSTGRESQL
        assert sre_config.data_provider_ip_addresses[0] == "2.3.4.5/32"
        assert sre_config.remote_desktop == remote_desktop_config
        assert sre_config.workspace_skus[0] == "Standard_D2s_v4"
        assert sre_config.research_user_ip_addresses[0] == "3.4.5.6/32"
        assert sre_config.software_packages == SoftwarePackageCategory.ANY
        assert sre_config.timezone == "Australia/Perth"

    def test_constructor_defaults(
        self, remote_desktop_config: ConfigSubsectionRemoteDesktopOpts
    ) -> None:
        sre_config = ConfigSectionSRE(admin_email_address="admin@example.com")
        assert sre_config.admin_email_address == "admin@example.com"
        assert sre_config.admin_ip_addresses == []
        assert sre_config.databases == []
        assert sre_config.data_provider_ip_addresses == []
        assert sre_config.remote_desktop == remote_desktop_config
        assert sre_config.workspace_skus == []
        assert sre_config.research_user_ip_addresses == []
        assert sre_config.software_packages == SoftwarePackageCategory.NONE
        assert sre_config.timezone == "Etc/UTC"

    def test_all_databases_must_be_unique(self) -> None:
        with pytest.raises(ValueError, match=r"All items must be unique."):
            ConfigSectionSRE(
                databases=[DatabaseSystem.POSTGRESQL, DatabaseSystem.POSTGRESQL],
            )



class TestConfigSubsectionRemoteDesktopOpts:
    def test_constructor(self) -> None:
        ConfigSubsectionRemoteDesktopOpts(allow_copy=True, allow_paste=True)

    def test_constructor_defaults(self) -> None:
        remote_desktop_config = ConfigSubsectionRemoteDesktopOpts()
        assert not all(
            (remote_desktop_config.allow_copy, remote_desktop_config.allow_paste)
        )
