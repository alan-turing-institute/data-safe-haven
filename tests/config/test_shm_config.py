import pytest
from pydantic import ValidationError

from data_safe_haven.config import SHMConfig
from data_safe_haven.config.config_sections import (
    ConfigSectionAzure,
    ConfigSectionSHM,
)
from data_safe_haven.context import Context
from data_safe_haven.exceptions import (
    DataSafeHavenTypeError,
)
from data_safe_haven.external import AzureApi


class TestConfig:
    def test_constructor(
        self, azure_config: ConfigSectionAzure, shm_config_section: ConfigSectionSHM
    ) -> None:
        config = SHMConfig(
            azure=azure_config,
            shm=shm_config_section,
        )
        assert isinstance(config.azure, ConfigSectionAzure)
        assert isinstance(config.shm, ConfigSectionSHM)

    def test_constructor_invalid(self, azure_config: ConfigSectionAzure) -> None:
        with pytest.raises(
            ValidationError,
            match=r"1 validation error for SHMConfig\nshm\n  Field required.*",
        ):
            SHMConfig(azure=azure_config)

    def test_template(self) -> None:
        config = SHMConfig.template()
        assert isinstance(config, SHMConfig)
        assert (
            config.azure.subscription_id
            == "ID of the Azure subscription that the TRE will be deployed to"
        )

    def test_template_validation(self) -> None:
        config = SHMConfig.template()
        with pytest.raises(DataSafeHavenTypeError):
            SHMConfig.from_yaml(config.to_yaml())

    def test_from_yaml(self, shm_config: SHMConfig, shm_config_yaml: str) -> None:
        config = SHMConfig.from_yaml(shm_config_yaml)
        assert config == shm_config
        assert isinstance(config.shm.fqdn, str)

    def test_from_remote(
        self, mocker, context, shm_config: SHMConfig, shm_config_yaml
    ) -> None:
        mock_method = mocker.patch.object(
            AzureApi, "download_blob", return_value=shm_config_yaml
        )
        config = SHMConfig.from_remote(context)

        assert config == shm_config
        mock_method.assert_called_once_with(
            SHMConfig.default_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_to_yaml(self, shm_config: SHMConfig, shm_config_yaml) -> None:
        assert shm_config.to_yaml() == shm_config_yaml

    def test_upload(self, mocker, context: Context, shm_config: SHMConfig) -> None:
        mock_method = mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        shm_config.upload(context)

        mock_method.assert_called_once_with(
            shm_config.to_yaml(),
            SHMConfig.default_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )
