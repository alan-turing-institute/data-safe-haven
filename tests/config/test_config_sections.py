import pytest
from pydantic import ValidationError

from data_safe_haven.config.config_sections import (
    ConfigSectionAzure,
    ConfigSectionDockerHub,
    ConfigSectionSHM,
    ConfigSectionSRE,
    ConfigSubsectionRemoteDesktopOpts,
    ConfigSubsectionStorageQuotaGB,
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

    def test_invalid_subscription_id(self):
        with pytest.raises(
            ValidationError,
            match=r"1 validation error for ConfigSectionAzure\nsubscription_id\n  Value error, Expected GUID",
        ):
            ConfigSectionAzure(
                location="uksouth",
                subscription_id="not_a_guid",
                tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            )

    def test_invalid_tenant_id(self):
        with pytest.raises(
            ValidationError,
            match=r"1 validation error for ConfigSectionAzure\ntenant_id\n  Value error, Expected GUID",
        ):
            ConfigSectionAzure(
                location="uksouth",
                subscription_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
                tenant_id="not_a_guid",
            )


class TestConfigSectionDockerHub:
    def test_constructor(self) -> None:
        ConfigSectionDockerHub(
            access_token="dummytoken",
            username="exampleuser",
        )

    def test_invalid_access_token(self):
        with pytest.raises(
            ValidationError,
            match="Value error, Expected valid string containing only letters, numbers, hyphens and underscores.",
        ):
            ConfigSectionDockerHub(
                access_token="not a valid access token",
                username="exampleuser",
            )

    def test_invalid_username(self):
        with pytest.raises(
            ValidationError,
            match="Value error, Expected valid string containing only letters, numbers, hyphens and underscores.",
        ):
            ConfigSectionDockerHub(
                access_token="dummytoken",
                username="not a valid username",
            )


class TestConfigSectionSHM:
    def test_constructor(self, config_section_shm_dict) -> None:
        ConfigSectionSHM(**config_section_shm_dict)

    def test_invalid_admin_group_id(self, config_section_shm_dict):
        config_section_shm_dict["admin_group_id"] = "not a guid"
        with pytest.raises(
            ValidationError,
            match=r"1 validation error for ConfigSectionSHM\nadmin_group_id\n  Value error, Expected GUID",
        ):
            ConfigSectionSHM(**config_section_shm_dict)

    def test_invalid_entra_tenant_id(self, config_section_shm_dict):
        config_section_shm_dict["entra_tenant_id"] = "not a guid"
        with pytest.raises(
            ValidationError,
            match=r"1 validation error for ConfigSectionSHM\nentra_tenant_id\n  Value error, Expected GUID",
        ):
            ConfigSectionSHM(**config_section_shm_dict)

    def test_invalid_fqdn(self, config_section_shm_dict):
        config_section_shm_dict["fqdn"] = "not a domain"
        with pytest.raises(
            ValidationError,
            match=r"1 validation error for ConfigSectionSHM\nfqdn\n  Value error, Expected valid fully qualified domain name",
        ):
            ConfigSectionSHM(**config_section_shm_dict)


class TestConfigSectionSRE:
    def test_constructor(
        self,
        config_subsection_remote_desktop: ConfigSubsectionRemoteDesktopOpts,
        config_subsection_storage_quota_gb: ConfigSubsectionStorageQuotaGB,
    ) -> None:
        sre_config = ConfigSectionSRE(
            admin_email_address="admin@example.com",
            admin_ip_addresses=["1.2.3.4"],
            databases=[DatabaseSystem.POSTGRESQL],
            data_provider_ip_addresses=["2.3.4.5"],
            remote_desktop=config_subsection_remote_desktop,
            workspace_skus=["Standard_D2s_v4"],
            research_user_ip_addresses=["3.4.5.6"],
            software_packages=SoftwarePackageCategory.ANY,
            storage_quota_gb=config_subsection_storage_quota_gb,
            timezone="Australia/Perth",
        )
        assert sre_config.admin_email_address == "admin@example.com"
        assert sre_config.admin_ip_addresses[0] == "1.2.3.4/32"
        assert sre_config.databases[0] == DatabaseSystem.POSTGRESQL
        assert sre_config.data_provider_ip_addresses[0] == "2.3.4.5/32"
        assert sre_config.remote_desktop == config_subsection_remote_desktop
        assert sre_config.research_user_ip_addresses[0] == "3.4.5.6/32"
        assert sre_config.software_packages == SoftwarePackageCategory.ANY
        assert sre_config.storage_quota_gb == config_subsection_storage_quota_gb
        assert sre_config.timezone == "Australia/Perth"
        assert sre_config.workspace_skus[0] == "Standard_D2s_v4"

    def test_constructor_defaults(
        self,
        config_subsection_remote_desktop: ConfigSubsectionRemoteDesktopOpts,
        config_subsection_storage_quota_gb: ConfigSubsectionStorageQuotaGB,
    ) -> None:
        sre_config = ConfigSectionSRE(
            admin_email_address="admin@example.com",
            remote_desktop=config_subsection_remote_desktop,
            storage_quota_gb=config_subsection_storage_quota_gb,
        )
        assert sre_config.admin_email_address == "admin@example.com"
        assert sre_config.admin_ip_addresses == []
        assert sre_config.databases == []
        assert sre_config.data_provider_ip_addresses == []
        assert sre_config.remote_desktop == config_subsection_remote_desktop
        assert sre_config.research_user_ip_addresses == []
        assert sre_config.software_packages == SoftwarePackageCategory.NONE
        assert sre_config.storage_quota_gb == config_subsection_storage_quota_gb
        assert sre_config.timezone == "Etc/UTC"
        assert sre_config.workspace_skus == []

    def test_all_databases_must_be_unique(self) -> None:
        with pytest.raises(ValueError, match=r"All items must be unique."):
            ConfigSectionSRE(
                databases=[DatabaseSystem.POSTGRESQL, DatabaseSystem.POSTGRESQL],
            )

    def test_ip_overlap_admin(self):
        with pytest.raises(ValueError, match="IP addresses must not overlap."):
            ConfigSectionSRE(
                admin_ip_addresses=["1.2.3.4", "1.2.3.4"],
            )

    def test_ip_overlap_data_provider(self):
        with pytest.raises(ValueError, match="IP addresses must not overlap."):
            ConfigSectionSRE(
                data_provider_ip_addresses=["1.2.3.4", "1.2.3.4"],
            )

    def test_ip_overlap_research_user(self):
        with pytest.raises(ValueError, match="IP addresses must not overlap."):
            ConfigSectionSRE(
                research_user_ip_addresses=["1.2.3.4", "1.2.3.4"],
            )

    @pytest.mark.parametrize(
        "addresses",
        [
            ["127.0.0.1", "127.0.0.1"],
            ["127.0.0.0/30", "127.0.0.2"],
            ["10.0.0.0/8", "10.255.0.0"],
            ["10.0.0.0/16", "10.0.255.42"],
            ["10.0.0.0/28", "10.0.0.0/32"],
        ],
    )
    def test_ip_overlap(self, addresses):
        with pytest.raises(ValueError, match="IP addresses must not overlap."):
            ConfigSectionSRE(
                research_user_ip_addresses=addresses,
            )


class TestConfigSubsectionRemoteDesktopOpts:
    def test_constructor(self) -> None:
        ConfigSubsectionRemoteDesktopOpts(allow_copy=True, allow_paste=True)

    def test_constructor_defaults(self) -> None:
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSubsectionRemoteDesktopOpts\nallow_copy\n  Field required",
        ):
            ConfigSubsectionRemoteDesktopOpts(allow_paste=False)

    def test_constructor_invalid_allow_copy(self) -> None:
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSubsectionRemoteDesktopOpts\nallow_paste\n  Input should be a valid boolean",
        ):
            ConfigSubsectionRemoteDesktopOpts(
                allow_copy=True,
                allow_paste="not a bool",
            )


class TestConfigSubsectionStorageQuotaGB:
    def test_constructor(self) -> None:
        ConfigSubsectionStorageQuotaGB(home=100, shared=100)

    def test_constructor_defaults(self) -> None:
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSubsectionStorageQuotaGB\nshared\n  Field required",
        ):
            ConfigSubsectionStorageQuotaGB(home=100)

    def test_constructor_invalid_type(self) -> None:
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSubsectionStorageQuotaGB\nshared\n  Input should be a valid integer",
        ):
            ConfigSubsectionStorageQuotaGB(
                home=100,
                shared="not a bool",
            )

    def test_constructor_invalid_value(self) -> None:
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSubsectionStorageQuotaGB\nhome\n  Input should be greater than or equal to 100",
        ):
            ConfigSubsectionStorageQuotaGB(
                home=50,
                shared=100,
            )
