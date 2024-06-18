import pytest
from pydantic import ValidationError

from data_safe_haven.config import SREConfig
from data_safe_haven.config.config_sections import (
    ConfigSectionAzure,
    ConfigSectionSHM,
    ConfigSectionSRE,
    ConfigSubsectionRemoteDesktopOpts,
)
from data_safe_haven.exceptions import (
    DataSafeHavenParameterError,
)
from data_safe_haven.external import AzureApi
from data_safe_haven.types import DatabaseSystem, SoftwarePackageCategory


class TestConfigSectionAzure:
    def test_constructor(self):
        ConfigSectionAzure(
            subscription_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        )


class TestConfigSectionSHM:
    def test_constructor(self):
        ConfigSectionSHM(
            entra_tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            fqdn="shm.acme.com",
            timezone="UTC",
        )

    def test_update(self, shm_config_section):
        assert shm_config_section.fqdn == "shm.acme.com"
        shm_config_section.update(fqdn="shm.example.com")
        assert shm_config_section.fqdn == "shm.example.com"

    def test_update_validation(self, shm_config_section):
        with pytest.raises(
            ValidationError,
            match=r"Value error, Expected valid fully qualified domain name, for example 'example.com'.*not an FQDN",
        ):
            shm_config_section.update(fqdn="not an FQDN")


class TestConfigSubsectionRemoteDesktopOpts:
    def test_constructor(self):
        ConfigSubsectionRemoteDesktopOpts(allow_copy=True, allow_paste=True)

    def test_constructor_defaults(self):
        remote_desktop_config = ConfigSubsectionRemoteDesktopOpts()
        assert not all(
            (remote_desktop_config.allow_copy, remote_desktop_config.allow_paste)
        )

    def test_update(self, remote_desktop_config):
        assert not all(
            (remote_desktop_config.allow_copy, remote_desktop_config.allow_paste)
        )
        remote_desktop_config.update(allow_copy=True, allow_paste=True)
        assert all(
            (remote_desktop_config.allow_copy, remote_desktop_config.allow_paste)
        )


class TestConfigSectionSRE:
    def test_constructor(self, remote_desktop_config):
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

    def test_constructor_defaults(self, remote_desktop_config):
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

    def test_all_databases_must_be_unique(self):
        with pytest.raises(ValueError, match=r"All items must be unique."):
            ConfigSectionSRE(
                databases=[DatabaseSystem.POSTGRESQL, DatabaseSystem.POSTGRESQL],
            )

    def test_update(self):
        sre_config = ConfigSectionSRE(admin_email_address="admin@example.com")
        assert sre_config.admin_email_address == "admin@example.com"
        assert sre_config.admin_ip_addresses == []
        assert sre_config.databases == []
        assert sre_config.data_provider_ip_addresses == []
        assert sre_config.workspace_skus == []
        assert sre_config.research_user_ip_addresses == []
        assert sre_config.software_packages == SoftwarePackageCategory.NONE
        assert sre_config.timezone == "Etc/UTC"
        sre_config.update(
            admin_email_address="admin@example.org",
            admin_ip_addresses=["1.2.3.4"],
            data_provider_ip_addresses=["2.3.4.5"],
            databases=[DatabaseSystem.MICROSOFT_SQL_SERVER],
            workspace_skus=["Standard_D8s_v4"],
            software_packages=SoftwarePackageCategory.ANY,
            user_ip_addresses=["3.4.5.6"],
            timezone="Australia/Perth",
        )
        assert sre_config.admin_email_address == "admin@example.org"
        assert sre_config.admin_ip_addresses == ["1.2.3.4/32"]
        assert sre_config.databases == [DatabaseSystem.MICROSOFT_SQL_SERVER]
        assert sre_config.data_provider_ip_addresses == ["2.3.4.5/32"]
        assert sre_config.workspace_skus == ["Standard_D8s_v4"]
        assert sre_config.research_user_ip_addresses == ["3.4.5.6/32"]
        assert sre_config.software_packages == SoftwarePackageCategory.ANY
        assert sre_config.timezone == "Australia/Perth"


class TestConfig:
    def test_constructor(self, azure_config, sre_config_section):
        config = SREConfig(
            azure=azure_config,
            sre=sre_config_section,
        )
        assert config.is_complete()

    def test_constructor_invalid(self, azure_config):
        with pytest.raises(
            ValidationError,
            match=r"1 validation error for SREConfig\nsre\n  Field required.*",
        ):
            SREConfig(azure=azure_config)

    def test_template(self):
        config = SREConfig.template()
        assert isinstance(config, SREConfig)
        assert (
            config.azure.subscription_id
            == "ID of the Azure subscription that the SRE will be deployed to"
        )

    def test_template_validation(self):
        config = SREConfig.template()
        with pytest.raises(DataSafeHavenParameterError):
            SREConfig.from_yaml(config.to_yaml())

    def test_from_yaml(self, sre_config, sre_config_yaml):
        config = SREConfig.from_yaml(sre_config_yaml)
        assert config == sre_config
        assert isinstance(config.sre.software_packages, SoftwarePackageCategory)

    def test_from_remote(self, mocker, context, sre_config, sre_config_yaml):
        mock_method = mocker.patch.object(
            AzureApi, "download_blob", return_value=sre_config_yaml
        )
        config = SREConfig.from_remote(context)

        assert config == sre_config
        mock_method.assert_called_once_with(
            SREConfig.filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_to_yaml(self, sre_config, sre_config_yaml):
        assert sre_config.to_yaml() == sre_config_yaml

    def test_upload(self, mocker, context, sre_config):
        mock_method = mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        sre_config.upload(context)

        mock_method.assert_called_once_with(
            sre_config.to_yaml(),
            SREConfig.filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )
