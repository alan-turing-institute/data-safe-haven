import pytest
from pydantic import ValidationError
from pytest import fixture

from data_safe_haven.config.config import (
    Config,
    ConfigSectionAzure,
    ConfigSectionPulumi,
    ConfigSectionSHM,
    ConfigSectionSRE,
    ConfigSectionTags,
    ConfigSubsectionRemoteDesktopOpts,
)
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.external import AzureApi
from data_safe_haven.utility.enums import DatabaseSystem, SoftwarePackageCategory
from data_safe_haven.version import __version__


@fixture
def azure_config(context):
    return ConfigSectionAzure(
        context=context,
        subscription_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
    )


class TestConfigSectionAzure:
    def test_constructor(self, context):
        azure_config = ConfigSectionAzure(
            context=context,
            subscription_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        )
        assert azure_config.location == context.location


@fixture
def pulumi_config():
    return ConfigSectionPulumi()


class TestConfigSectionPulumi:
    def test_constructor_defaults(self):
        pulumi_config = ConfigSectionPulumi()
        assert pulumi_config.encryption_key_name == "pulumi-encryption-key"
        assert pulumi_config.stacks == {}
        assert pulumi_config.storage_container_name == "pulumi"


@fixture
def shm_config(context):
    return ConfigSectionSHM(
        context=context,
        aad_tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        admin_email_address="admin@example.com",
        admin_ip_addresses=["0.0.0.0"],  # noqa: S104
        fqdn="shm.acme.com",
        timezone="UTC",
    )


class TestConfigSectionSHM:
    def test_constructor(self, context):
        shm_config = ConfigSectionSHM(
            context=context,
            aad_tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            admin_email_address="admin@example.com",
            admin_ip_addresses=["0.0.0.0"],  # noqa: S104
            fqdn="shm.acme.com",
            timezone="UTC",
        )
        assert shm_config.name == context.shm_name

    def test_update(self, shm_config):
        assert shm_config.fqdn == "shm.acme.com"
        shm_config.update(fqdn="shm.example.com")
        assert shm_config.fqdn == "shm.example.com"

    def test_update_validation(self, shm_config):
        with pytest.raises(
            ValidationError,
            match="Value error, Expected valid email address.*not an email address",
        ):
            shm_config.update(admin_email_address="not an email address")


@fixture
def remote_desktop_config():
    return ConfigSubsectionRemoteDesktopOpts()


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
            databases=[DatabaseSystem.POSTGRESQL],
            data_provider_ip_addresses=["0.0.0.0"],  # noqa: S104
            index=1,
            remote_desktop=remote_desktop_config,
            workspace_skus=["Standard_D2s_v4"],
            research_user_ip_addresses=["0.0.0.0"],  # noqa: S104
            software_packages=SoftwarePackageCategory.ANY,
        )
        assert sre_config.data_provider_ip_addresses[0] == "0.0.0.0/32"

    def test_constructor_defaults(self, remote_desktop_config):
        sre_config = ConfigSectionSRE(index=1)
        assert sre_config.databases == []
        assert sre_config.data_provider_ip_addresses == []
        assert sre_config.remote_desktop == remote_desktop_config
        assert sre_config.workspace_skus == []
        assert sre_config.research_user_ip_addresses == []
        assert sre_config.software_packages == SoftwarePackageCategory.NONE

    def test_all_databases_must_be_unique(self):
        with pytest.raises(ValueError, match="All items must be unique."):
            ConfigSectionSRE(
                index=1,
                databases=[DatabaseSystem.POSTGRESQL, DatabaseSystem.POSTGRESQL],
            )

    def test_update(self):
        sre_config = ConfigSectionSRE(index=1)
        assert sre_config.databases == []
        assert sre_config.data_provider_ip_addresses == []
        assert sre_config.workspace_skus == []
        assert sre_config.research_user_ip_addresses == []
        assert sre_config.software_packages == SoftwarePackageCategory.NONE
        sre_config.update(
            data_provider_ip_addresses=["0.0.0.0"],  # noqa: S104
            databases=[DatabaseSystem.MICROSOFT_SQL_SERVER],
            workspace_skus=["Standard_D8s_v4"],
            software_packages=SoftwarePackageCategory.ANY,
            user_ip_addresses=["0.0.0.0"],  # noqa: S104
        )
        assert sre_config.databases == [DatabaseSystem.MICROSOFT_SQL_SERVER]
        assert sre_config.data_provider_ip_addresses == ["0.0.0.0/32"]
        assert sre_config.workspace_skus == ["Standard_D8s_v4"]
        assert sre_config.research_user_ip_addresses == ["0.0.0.0/32"]
        assert sre_config.software_packages == SoftwarePackageCategory.ANY


@fixture
def tags_config(context):
    return ConfigSectionTags(context)


class TestConfigSectionTags:
    def test_constructor(self, context):
        tags_config = ConfigSectionTags(context)
        assert tags_config.deployment == "Acme Deployment"
        assert tags_config.deployed_by == "Python"
        assert tags_config.project == "Data Safe Haven"
        assert tags_config.version == __version__

    def test_model_dump(self, tags_config):
        tags_dict = tags_config.model_dump()
        assert all(
            ("deployment", "deployed_by", "project", "version" in tags_dict.keys())
        )
        assert tags_dict["deployment"] == "Acme Deployment"
        assert tags_dict["version"] == __version__


@fixture
def config_no_sres(context, azure_config, pulumi_config, shm_config):
    return Config(
        context=context,
        azure=azure_config,
        pulumi=pulumi_config,
        shm=shm_config,
    )


@fixture
def config_sres(context, azure_config, pulumi_config, shm_config):
    sre_config_1 = ConfigSectionSRE(index=1)
    sre_config_2 = ConfigSectionSRE(index=2)
    return Config(
        context=context,
        azure=azure_config,
        pulumi=pulumi_config,
        shm=shm_config,
        sres={
            "sre1": sre_config_1,
            "sre2": sre_config_2,
        },
    )


@fixture
def mock_key_vault_key(monkeypatch):
    class MockKeyVaultKey:
        def __init__(self, key_name, key_vault_name):
            self.key_name = key_name
            self.key_vault_name = key_vault_name
            self.id = "mock_key/version"

    def mock_get_keyvault_key(self, key_name, key_vault_name):  # noqa: ARG001
        return MockKeyVaultKey(key_name, key_vault_name)

    monkeypatch.setattr(AzureApi, "get_keyvault_key", mock_get_keyvault_key)


class TestConfig:
    def test_constructor(self, context, azure_config, pulumi_config, shm_config):
        config = Config(
            context=context,
            azure=azure_config,
            pulumi=pulumi_config,
            shm=shm_config,
        )
        assert not config.sres

    def test_all_sre_indices_must_be_unique(
        self, context, azure_config, pulumi_config, shm_config
    ):
        with pytest.raises(ValueError, match="all SRE indices must be unique"):
            sre_config_1 = ConfigSectionSRE(index=1)
            sre_config_2 = ConfigSectionSRE(index=1)
            Config(
                context=context,
                azure=azure_config,
                pulumi=pulumi_config,
                shm=shm_config,
                sres={
                    "sre1": sre_config_1,
                    "sre2": sre_config_2,
                },
            )

    def test_work_directory(self, config_sres):
        config = config_sres
        assert config.work_directory == config.context.work_directory

    def test_pulumi_encryption_key(
        self, config_sres, mock_key_vault_key  # noqa: ARG002
    ):
        key = config_sres.pulumi_encryption_key
        assert key.key_name == config_sres.pulumi.encryption_key_name
        assert key.key_vault_name == config_sres.context.key_vault_name

    def test_pulumi_encryption_key_version(
        self, config_sres, mock_key_vault_key  # noqa: ARG002
    ):
        version = config_sres.pulumi_encryption_key_version
        assert version == "version"

    @pytest.mark.parametrize("require_sres,expected", [(False, True), (True, False)])
    def test_is_complete_no_sres(self, config_no_sres, require_sres, expected):
        assert config_no_sres.is_complete(require_sres=require_sres) is expected

    @pytest.mark.parametrize("require_sres", [False, True])
    def test_is_complete_sres(self, config_sres, require_sres):
        assert config_sres.is_complete(require_sres=require_sres)

    @pytest.mark.parametrize(
        "value,expected",
        [("Test SRE", "testsre"), ("%*aBc", "abc"), ("MY_SRE", "mysre")],
    )
    def test_sanitise_sre_name(self, value, expected):
        assert Config.sanitise_sre_name(value) == expected

    def test_sre(self, config_sres):
        sre1, sre2 = config_sres.sre("sre1"), config_sres.sre("sre2")
        assert sre1.index == 1
        assert sre2.index == 2
        assert sre1 != sre2

    def test_sre_invalid(self, config_sres):
        with pytest.raises(DataSafeHavenConfigError) as exc:
            config_sres.sre("sre3")
            assert "SRE sre3 does not exist" in exc

    def test_template(self, context):
        config = Config.template(context)
        assert isinstance(config, Config)
        assert config.azure.subscription_id == "Azure subscription ID"

    def test_template_validation(self, context):
        config = Config.template(context)
        with pytest.raises(DataSafeHavenParameterError):
            Config.from_yaml(context, config.to_yaml())

    def test_from_yaml(self, config_sres, context, config_yaml):
        config = Config.from_yaml(context, config_yaml)
        assert config == config_sres
        assert isinstance(
            config.sres["sre1"].software_packages, SoftwarePackageCategory
        )

    def test_from_remote(
        self, context, config_sres, mock_download_blob  # noqa: ARG002
    ):
        config = Config.from_remote(context)
        assert config == config_sres

    def test_to_yaml(self, config_sres, config_yaml):
        assert config_sres.to_yaml() == config_yaml

    def test_upload(self, config_sres, mock_upload_blob):  # noqa: ARG002
        config_sres.upload()
