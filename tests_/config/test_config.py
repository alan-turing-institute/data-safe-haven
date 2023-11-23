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
from data_safe_haven.external import AzureApi
from data_safe_haven.utility.enums import DatabaseSystem, SoftwarePackageCategory
from data_safe_haven.version import __version__


@fixture
def azure_config(context):
    return ConfigSectionAzure.from_context(
        context=context,
        subscription_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
    )


class TestConfigSectionAzure:
    def test_constructor(self):
        ConfigSectionAzure(
            admin_group_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            location="uksouth",
            subscription_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        )

    def test_from_context(self, context):
        azure_config = ConfigSectionAzure.from_context(
            context=context,
            subscription_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        )
        assert azure_config.location == context.location


@fixture
def pulumi_config():
    return ConfigSectionPulumi(encryption_key_version="lorem")


class TestConfigSectionPulumi:
    def test_constructor_defaults(self):
        pulumi_config = ConfigSectionPulumi(encryption_key_version="lorem")
        assert pulumi_config.encryption_key_name == "pulumi-encryption-key"
        assert pulumi_config.stacks == {}
        assert pulumi_config.storage_container_name == "pulumi"


@fixture
def shm_config(context):
    return ConfigSectionSHM.from_context(
        context=context,
        aad_tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        admin_email_address="admin@example.com",
        admin_ip_addresses=["0.0.0.0"],  # noqa: S104
        fqdn="shm.acme.com",
        timezone="UTC",
    )


class TestConfigSectionSHM:
    def test_constructor(self):
        ConfigSectionSHM(
            aad_tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            admin_email_address="admin@example.com",
            admin_ip_addresses=["0.0.0.0"],  # noqa: S104
            fqdn="shm.acme.com",
            name="ACME SHM",
            timezone="UTC",
        )

    def test_from_context(self, context):
        shm_config = ConfigSectionSHM.from_context(
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
        shm_config.update(fqdn="modified")
        assert shm_config.fqdn == "modified"

    def test_update_validation(self, shm_config):
        with pytest.raises(ValidationError) as exc:
            shm_config.update(admin_email_address="not an email address")
            assert "Value error, Expected valid email address" in exc
            assert "not an email address" in exc


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
            index=0,
            remote_desktop=remote_desktop_config,
            workspace_skus=["Standard_D2s_v4"],
            research_user_ip_addresses=["0.0.0.0"],  # noqa: S104
            software_packages=SoftwarePackageCategory.ANY,
        )
        assert sre_config.data_provider_ip_addresses[0] == "0.0.0.0/32"

    def test_constructor_defaults(self, remote_desktop_config):
        sre_config = ConfigSectionSRE(index=0)
        assert sre_config.databases == []
        assert sre_config.data_provider_ip_addresses == []
        assert sre_config.remote_desktop == remote_desktop_config
        assert sre_config.workspace_skus == []
        assert sre_config.research_user_ip_addresses == []
        assert sre_config.software_packages == SoftwarePackageCategory.NONE

    def test_all_databases_must_be_unique(self):
        with pytest.raises(ValueError) as exc:
            ConfigSectionSRE(
                index=0,
                databases=[DatabaseSystem.POSTGRESQL, DatabaseSystem.POSTGRESQL],
            )
            assert "all databases must be unique" in exc

    def test_update(self):
        sre_config = ConfigSectionSRE(index=0)
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
    return ConfigSectionTags.from_context(context)


class TestConfigSectionTags:
    def test_constructor(self):
        tags_config = ConfigSectionTags(deployment="Test Deployment")
        assert tags_config.deployment == "Test Deployment"
        assert tags_config.deployed_by == "Python"
        assert tags_config.project == "Data Safe Haven"
        assert tags_config.version == __version__

    def test_from_context(self, context):
        tags_config = ConfigSectionTags.from_context(context)
        assert tags_config.deployment == "Acme Deployment"
        assert tags_config.deployed_by == "Python"
        assert tags_config.project == "Data Safe Haven"
        assert tags_config.version == __version__


@fixture
def config_no_sres(context, azure_config, pulumi_config, shm_config, tags_config):
    return Config(
        context=context,
        azure=azure_config,
        pulumi=pulumi_config,
        shm=shm_config,
        tags=tags_config
    )


@fixture
def config_sres(context, azure_config, pulumi_config, shm_config, tags_config):
    sre_config_1 = ConfigSectionSRE(index=0)
    sre_config_2 = ConfigSectionSRE(index=1)
    return Config(
        context=context,
        azure=azure_config,
        pulumi=pulumi_config,
        shm=shm_config,
        sres={
            "sre1": sre_config_1,
            "sre2": sre_config_2,
        },
        tags=tags_config
    )


@fixture
def config_yaml():
    return """azure:
  admin_group_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
  location: uksouth
  subscription_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
  tenant_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
context:
  admin_group_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
  location: uksouth
  name: Acme Deployment
  subscription_name: Data Safe Haven (Acme)
pulumi:
  encryption_key_name: pulumi-encryption-key
  encryption_key_version: lorem
  stacks: {}
  storage_container_name: pulumi
shm:
  aad_tenant_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
  admin_email_address: admin@example.com
  admin_ip_addresses:
  - 0.0.0.0/32
  fqdn: shm.acme.com
  name: acmedeployment
  timezone: UTC
sres:
  sre1:
    data_provider_ip_addresses: []
    databases: []
    index: 0
    remote_desktop:
      allow_copy: false
      allow_paste: false
    research_user_ip_addresses: []
    software_packages: none
    workspace_skus: []
  sre2:
    data_provider_ip_addresses: []
    databases: []
    index: 1
    remote_desktop:
      allow_copy: false
      allow_paste: false
    research_user_ip_addresses: []
    software_packages: none
    workspace_skus: []
tags:
  deployment: Acme Deployment
"""


class TestConfig:
    def test_constructor_defaults(self, context):
        config = Config(context=context)
        assert config.context == context
        assert not any(
            (config.azure, config.pulumi, config.shm, config.tags, config.sres)
        )

    @pytest.mark.parametrize("require_sres", [False, True])
    def test_is_complete_bare(self, context, require_sres):
        config = Config(context=context)
        assert config.is_complete(require_sres=require_sres) is False

    def test_constructor(self, context, azure_config, pulumi_config, shm_config, tags_config):
        config = Config(
            context=context,
            azure=azure_config,
            pulumi=pulumi_config,
            shm=shm_config,
            tags=tags_config
        )
        assert not config.sres

    @pytest.mark.parametrize("require_sres,expected", [(False, True), (True, False)])
    def test_is_complete_no_sres(self, config_no_sres, require_sres, expected):
        assert config_no_sres.is_complete(require_sres=require_sres) is expected

    @pytest.mark.parametrize("require_sres", [False, True])
    def test_is_complete_sres(self, config_sres, require_sres):
        assert config_sres.is_complete(require_sres=require_sres)

    def test_work_directory(self, config_sres):
        config = config_sres
        assert config.work_directory == config.context.work_directory

    def test_to_yaml(self, config_sres, config_yaml):
        assert config_sres.to_yaml() == config_yaml

    def test_from_yaml(self, config_sres, config_yaml):
        config = Config.from_yaml(config_yaml)
        assert config == config_sres
        assert isinstance(config.sres["sre1"].software_packages, SoftwarePackageCategory)

    def test_upload(self, config_sres, monkeypatch):
        def mock_upload_blob(
            self,
            blob_data: bytes | str,
            blob_name: str,
            resource_group_name: str,
            storage_account_name: str,
            storage_container_name: str,
        ):
            pass

        monkeypatch.setattr(AzureApi, "upload_blob", mock_upload_blob)
        config_sres.upload()

    def test_from_remote(self, context, config_sres, config_yaml, monkeypatch):
        def mock_download_blob(
            self,
            blob_name: str,
            resource_group_name: str,
            storage_account_name: str,
            storage_container_name: str,
        ):
            assert blob_name == context.config_filename
            assert resource_group_name == context.resource_group_name
            assert storage_account_name == context.storage_account_name
            assert storage_container_name == context.storage_container_name
            return config_yaml

        monkeypatch.setattr(AzureApi, "download_blob", mock_download_blob)
        config = Config.from_remote(context)
        assert config == config_sres
