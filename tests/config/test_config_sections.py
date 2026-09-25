import pytest
from pydantic import ValidationError

from data_safe_haven.config.config_sections import (
    ConfigSectionAzure,
    ConfigSectionDockerHub,
    ConfigSectionMonitoring,
    ConfigSectionSHM,
    ConfigSectionSRE,
    ConfigSectionUserServices,
    ConfigSubsectionNexus,
    ConfigSubsectionRemoteDesktopOpts,
    ConfigSubsectionStorageQuotaGB,
)
from data_safe_haven.types import (
    AzureServiceTag,
    DatabaseSystem,
    SoftwarePackageCategory,
)


class TestConfigSectionAzure:
    def test_constructor(self) -> None:
        ConfigSectionAzure(
            location="uksouth",
            subscription_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        )

    def test_invalid_location(self):
        with pytest.raises(
            ValidationError, match=r"Value error, Expected valid Azure location"
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
            match=r"Value error, Expected valid string containing only letters, numbers, hyphens and underscores.",
        ):
            ConfigSectionDockerHub(
                access_token="not a valid access token",
                username="exampleuser",
            )

    def test_invalid_username(self):
        with pytest.raises(
            ValidationError,
            match=r"Value error, Expected valid string containing only letters, numbers, hyphens and underscores.",
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


class TestConfigSectionUserServices:
    def test_constructor(self):
        user_provided_quota: int = 20
        user_services_config = ConfigSectionUserServices(
            nexus=ConfigSubsectionNexus(persistent_quota_gb=user_provided_quota)
        )

        assert user_services_config.nexus is not None
        assert user_services_config.nexus.persistent_quota_gb == user_provided_quota

    def test_constructor_defaults(self):
        default_quota_size: int = 10
        user_services_config = ConfigSectionUserServices()
        assert user_services_config.nexus is not None
        assert user_services_config.nexus.persistent_quota_gb == default_quota_size

    def test_invalid_nexus_quota(self):
        with pytest.raises(ValueError, match=r"Input should be greater than 0"):
            ConfigSectionUserServices(
                nexus=ConfigSubsectionNexus(persistent_quota_gb=0)
            )


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
        assert not sre_config.allow_workspace_internet
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
        with pytest.raises(ValueError, match=r"IP addresses must not overlap."):
            ConfigSectionSRE(
                admin_ip_addresses=["1.2.3.4", "1.2.3.4"],
            )

    def test_ip_overlap_data_provider(self):
        with pytest.raises(ValueError, match=r"IP addresses must not overlap."):
            ConfigSectionSRE(
                data_provider_ip_addresses=["1.2.3.4", "1.2.3.4"],
            )

    def test_ip_overlap_research_user(self):
        with pytest.raises(ValueError, match=r"IP addresses must not overlap."):
            ConfigSectionSRE(
                research_user_ip_addresses=["1.2.3.4", "1.2.3.4"],
            )

    def test_research_user_tag_internet(
        self,
        config_subsection_remote_desktop: ConfigSubsectionRemoteDesktopOpts,
        config_subsection_storage_quota_gb: ConfigSubsectionStorageQuotaGB,
    ):
        sre_config = ConfigSectionSRE(
            admin_email_address="admin@example.com",
            remote_desktop=config_subsection_remote_desktop,
            storage_quota_gb=config_subsection_storage_quota_gb,
            research_user_ip_addresses="Internet",
        )
        assert isinstance(sre_config.research_user_ip_addresses, AzureServiceTag)
        assert sre_config.research_user_ip_addresses == "Internet"

    def test_research_user_tag_invalid(self):
        with pytest.raises(ValueError, match="Input should be 'Internet'"):
            ConfigSectionSRE(research_user_ip_addresses="Not a tag")

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
        with pytest.raises(ValueError, match=r"IP addresses must not overlap."):
            ConfigSectionSRE(
                research_user_ip_addresses=addresses,
            )

    def test_internet_and_packages_validation(
        self,
        config_subsection_remote_desktop: ConfigSubsectionRemoteDesktopOpts,
        config_subsection_storage_quota_gb: ConfigSubsectionStorageQuotaGB,
    ):
        sre_config = ConfigSectionSRE(
            admin_email_address="admin@example.com",
            remote_desktop=config_subsection_remote_desktop,
            storage_quota_gb=config_subsection_storage_quota_gb,
            allow_workspace_internet=True,
            software_packages=SoftwarePackageCategory.ANY,
        )
        assert sre_config.allow_workspace_internet
        assert sre_config.software_packages == SoftwarePackageCategory.ANY

        sre_config = ConfigSectionSRE(
            admin_email_address="admin@example.com",
            remote_desktop=config_subsection_remote_desktop,
            storage_quota_gb=config_subsection_storage_quota_gb,
            allow_workspace_internet=False,
            software_packages=SoftwarePackageCategory.NONE,
        )
        assert not sre_config.allow_workspace_internet
        assert sre_config.software_packages == SoftwarePackageCategory.NONE

        with pytest.raises(
            ValueError,
            match=r"When `allow_workspace_internet` is `true`, `software_packages` must be `any`",
        ):
            ConfigSectionSRE(
                admin_email_address="admin@example.com",
                remote_desktop=config_subsection_remote_desktop,
                storage_quota_gb=config_subsection_storage_quota_gb,
                allow_workspace_internet=True,
                software_packages=SoftwarePackageCategory.NONE,
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


class TestConfigSectionMonitoring:
    def test_constructor(self) -> None:
        ConfigSectionMonitoring(
            log_level="debug", retention_period=10, sampling_interval=30
        )

    def test_constructor_defaults(self) -> None:
        section = ConfigSectionMonitoring()
        assert section.log_level == "info"
        assert section.retention_period == 30
        assert section.sampling_interval == 60

    def test_constructor_undefaults(self) -> None:
        section = ConfigSectionMonitoring(
            log_level="debug", retention_period=7, sampling_interval=21
        )
        assert section.log_level == "debug"
        assert section.retention_period == 7
        assert section.sampling_interval == 21

    def test_constructor_valid_log_level(self) -> None:
        ConfigSectionMonitoring(log_level="error")
        ConfigSectionMonitoring(log_level="warn")
        ConfigSectionMonitoring(log_level="info")
        ConfigSectionMonitoring(log_level="debug")
        ConfigSectionMonitoring(log_level="trace")

    def test_constructor_invalid_log_level(self) -> None:
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSectionMonitoring\nlog_level\n  Value error, Logging level must be one of error, warn, info, debug or trace",
        ):
            ConfigSectionMonitoring(log_level="critical")
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSectionMonitoring\nlog_level\n  Input should be a valid string",
        ):
            ConfigSectionMonitoring(log_level=3)

    def test_constructor_valid_retention_period(self) -> None:
        ConfigSectionMonitoring(retention_period=30)
        ConfigSectionMonitoring(retention_period=31)
        ConfigSectionMonitoring(retention_period=99)
        ConfigSectionMonitoring(retention_period=729)
        ConfigSectionMonitoring(retention_period=730)
        section = ConfigSectionMonitoring(retention_period="27")
        assert section.retention_period == 27

    def test_constructor_invalid_retention_period(self) -> None:
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSectionMonitoring\nretention_period\n  Input should be greater than 0",
        ):
            ConfigSectionMonitoring(retention_period=0)
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSectionMonitoring\nretention_period\n  Input should be greater than 0",
        ):
            ConfigSectionMonitoring(retention_period=29)
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSectionMonitoring\nretention_period\n  Value error, Retention period must be between 30 and 730 days \(inclusive\)",
        ):
            ConfigSectionMonitoring(retention_period=731)
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSectionMonitoring\nretention_period\n  Value error, Retention period must be between 30 and 730 days \(inclusive\)",
        ):
            ConfigSectionMonitoring(retention_period=731)
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSectionMonitoring\nretention_period\n  Input should be greater than 0",
        ):
            ConfigSectionMonitoring(retention_period="0")

    def test_constructor_valid_sampling_interval(self) -> None:
        ConfigSectionMonitoring(sampling_interval=1)
        ConfigSectionMonitoring(sampling_interval=2)
        ConfigSectionMonitoring(sampling_interval=60)
        ConfigSectionMonitoring(sampling_interval=9999)
        section = ConfigSectionMonitoring(sampling_interval="87")
        assert section.sampling_interval == 87

    def test_constructor_invalid_sampling_interval(self) -> None:
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSectionMonitoring\nsampling_interval\n  Input should be greater than 0",
        ):
            ConfigSectionMonitoring(sampling_interval=0)
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSectionMonitoring\nsampling_interval\n  Input should be greater than 0",
        ):
            ConfigSectionMonitoring(sampling_interval=-1)
        with pytest.raises(
            ValueError,
            match=r"1 validation error for ConfigSectionMonitoring\nsampling_interval\n  Input should be greater than 0",
        ):
            ConfigSectionMonitoring(sampling_interval="0")
