import pytest
from pydantic import ValidationError
from pytest_mock import MockerFixture

from data_safe_haven.config import Context, SREConfig
from data_safe_haven.config.config_sections import (
    ConfigSectionAzure,
    ConfigSectionDockerHub,
    ConfigSectionSRE,
)
from data_safe_haven.exceptions import (
    DataSafeHavenTypeError,
)
from data_safe_haven.external import AzureSdk
from data_safe_haven.types import SoftwarePackageCategory


class TestConfig:
    def test_constructor(
        self,
        config_section_azure: ConfigSectionAzure,
        config_section_dockerhub: ConfigSectionDockerHub,
        config_section_sre: ConfigSectionSRE,
    ) -> None:
        config = SREConfig(
            azure=config_section_azure,
            description="Sandbox Project",
            dockerhub=config_section_dockerhub,
            name="sandbox",
            sre=config_section_sre,
        )
        assert isinstance(config.azure, ConfigSectionAzure)
        assert isinstance(config.name, str)
        assert isinstance(config.sre, ConfigSectionSRE)

    def test_constructor_invalid(
        self,
        config_section_azure: ConfigSectionAzure,
        config_section_dockerhub: ConfigSectionDockerHub,
    ) -> None:
        with pytest.raises(
            ValidationError,
            match=r"1 validation error for SREConfig\nsre\n  Field required.*",
        ):
            SREConfig(
                azure=config_section_azure,
                description="Sandbox Project",
                dockerhub=config_section_dockerhub,
                name="sandbox",
            )

    @pytest.mark.parametrize(
        "name",
        [
            r"has spaces",
            r"has!special@characters£",
            r"has\tnon\rprinting\ncharacters",
            r"",
        ],
    )
    def test_constructor_invalid_name(
        self,
        config_section_azure: ConfigSectionAzure,
        config_section_dockerhub: ConfigSectionDockerHub,
        config_section_sre: ConfigSectionSRE,
        name: str,
    ) -> None:
        with pytest.raises(
            ValidationError,
            match=r"1 validation error for SREConfig\nname\n  Value error, Expected valid string.*",
        ):
            SREConfig(
                azure=config_section_azure,
                description="Sandbox Project",
                dockerhub=config_section_dockerhub,
                name=name,
                sre=config_section_sre,
            )

    def test_template(self) -> None:
        config = SREConfig.template()
        assert isinstance(config, SREConfig)
        assert (
            config.azure.subscription_id
            == "ID of the Azure subscription that the SRE will be deployed to"
        )

    def test_template_validation(self) -> None:
        config = SREConfig.template()
        with pytest.raises(DataSafeHavenTypeError):
            SREConfig.from_yaml(config.to_yaml())

    @pytest.mark.parametrize(
        "tier,allow_internet,copy,paste,packages",
        [
            (0, True, True, True, SoftwarePackageCategory.ANY),
            (1, True, True, True, SoftwarePackageCategory.ANY),
            (2, False, False, False, SoftwarePackageCategory.ANY),
            (3, False, False, False, SoftwarePackageCategory.PRE_APPROVED),
            (4, False, False, False, SoftwarePackageCategory.NONE),
        ],
    )
    def test_template_tiers(
        self,
        tier: int,
        allow_internet: bool,  # noqa: FBT001
        copy: bool,  # noqa: FBT001
        paste: bool,  # noqa: FBT001
        packages: SoftwarePackageCategory,
    ) -> None:
        config = SREConfig.template(tier=tier)
        assert config.sre.allow_workspace_internet == allow_internet
        assert config.sre.remote_desktop.allow_copy == copy
        assert config.sre.remote_desktop.allow_paste == paste
        assert config.sre.software_packages == packages

    def test_from_yaml(self, sre_config: SREConfig, sre_config_yaml: str) -> None:
        config = SREConfig.from_yaml(sre_config_yaml)
        assert config == sre_config
        assert isinstance(config.sre.software_packages, SoftwarePackageCategory)

    def test_from_remote(
        self,
        mocker: MockerFixture,
        context: Context,
        sre_config: SREConfig,
        sre_config_yaml: str,
    ) -> None:
        mock_method = mocker.patch.object(
            AzureSdk, "download_blob", return_value=sre_config_yaml
        )
        config = SREConfig.from_remote(context)

        assert config == sre_config
        mock_method.assert_called_once_with(
            SREConfig.default_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_to_yaml(self, sre_config: SREConfig, sre_config_yaml: str) -> None:
        assert sre_config.to_yaml() == sre_config_yaml

    def test_upload(
        self, mocker: MockerFixture, context: Context, sre_config: SREConfig
    ) -> None:
        mock_method = mocker.patch.object(AzureSdk, "upload_blob", return_value=None)
        sre_config.upload(context)

        mock_method.assert_called_once_with(
            sre_config.to_yaml(),
            SREConfig.default_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_sre_config_yaml_name(self, sre_config: SREConfig) -> None:
        assert sre_config.filename == "sre-sandbox.yaml"


def test_sre_config_diff_uses_local_remote_orientation(sre_config):
    remote = sre_config.model_copy(deep=True)
    remote.description = "Remote description"

    changes = sre_config.diff(remote)

    assert changes[0:2] == ["--- remote\n", "+++ local\n"]
    assert "-description: Remote description\n" in changes
    assert f"+description: {sre_config.description}\n" in changes
    assert sre_config.diff(sre_config.model_copy(deep=True)) == []
