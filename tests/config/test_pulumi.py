from pytest import raises

from data_safe_haven.config import DSHPulumiConfig, DSHPulumiProject
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenTypeError,
)
from data_safe_haven.external import AzureSdk


class TestDSHPulumiProject:
    def test_pulumi_project(self, pulumi_project):
        assert isinstance(pulumi_project.stack_config, dict)
        assert "azure-native:location" in pulumi_project.stack_config.keys()
        assert pulumi_project.stack_config.get("azure-native:location") == "uksouth"

    def test_dump(self, pulumi_project, pulumi_project_stack_config):
        d = pulumi_project.model_dump()
        assert d.get("stack_config") == pulumi_project_stack_config

    def test_eq(self, pulumi_project):
        assert pulumi_project == pulumi_project.model_copy(deep=True)

    def test_not_eq(self, pulumi_project, pulumi_project_other):
        assert pulumi_project != pulumi_project_other


class TestDSHPulumiConfig:
    def test_pulumi_config(self, pulumi_project):
        config = DSHPulumiConfig(
            encrypted_key="NZVaEDfeuIPR7N8Dwnpx",
            projects={"acmedeployment": pulumi_project},
        )
        assert config.projects["acmedeployment"] == pulumi_project
        assert isinstance(config.encrypted_key, str)
        assert config.encrypted_key == "NZVaEDfeuIPR7N8Dwnpx"

    def test_getitem(self, pulumi_config, pulumi_project, pulumi_project_other):
        assert pulumi_config["acmedeployment"] == pulumi_project
        assert pulumi_config["other_project"] == pulumi_project_other

    def test_getitem_type_error(self, pulumi_config):
        with raises(TypeError, match="'key' must be a string."):
            pulumi_config[0]

    def test_getitem_index_error(self, pulumi_config):
        with raises(KeyError, match="No configuration for DSH Pulumi Project Ringo."):
            pulumi_config["Ringo"]

    def test_delitem(self, pulumi_config):
        assert len(pulumi_config.projects) == 2
        del pulumi_config["acmedeployment"]
        assert len(pulumi_config.projects) == 1

    def test_delitem_value_error(self, pulumi_config):
        with raises(TypeError, match="'key' must be a string."):
            del pulumi_config[-1]

    def test_delitem_index_error(self, pulumi_config):
        with raises(KeyError, match="No configuration for DSH Pulumi Project Ringo."):
            del pulumi_config["Ringo"]

    def test_setitem(self, pulumi_config, pulumi_project):
        del pulumi_config["acmedeployment"]
        assert len(pulumi_config.project_names) == 1
        assert "acmedeployment" not in pulumi_config.project_names
        pulumi_config["acmedeployment"] = pulumi_project
        assert len(pulumi_config.project_names) == 2
        assert "acmedeployment" in pulumi_config.project_names

    def test_setitem_type_error(self, pulumi_config):
        with raises(TypeError, match="'key' must be a string."):
            pulumi_config[1] = 5

    def test_setitem_value_error(self, pulumi_config):
        with raises(ValueError, match="Stack other_project already exists."):
            pulumi_config["other_project"] = 5

    def test_project_names(self, pulumi_config):
        assert "acmedeployment" in pulumi_config.project_names

    def test_to_yaml(self, pulumi_config):
        yaml = pulumi_config.to_yaml()
        assert isinstance(yaml, str)
        assert "projects:" in yaml
        assert "stack_config:" in yaml
        assert "azure-native:location: uksouth" in yaml

    def test_from_yaml(self, pulumi_config_yaml):
        pulumi_config = DSHPulumiConfig.from_yaml(pulumi_config_yaml)
        assert len(pulumi_config.projects) == 2
        assert "acmedeployment" in pulumi_config.project_names
        assert isinstance(pulumi_config["acmedeployment"], DSHPulumiProject)
        assert "other_project" in pulumi_config.project_names
        assert isinstance(pulumi_config["other_project"], DSHPulumiProject)
        assert (
            pulumi_config["acmedeployment"].stack_config.get("data-safe-haven:variable")
            == 5
        )

    def test_from_yaml_invalid_yaml(self):
        with raises(
            DataSafeHavenConfigError,
            match="Could not parse Pulumi configuration as YAML.",
        ):
            DSHPulumiConfig.from_yaml("a: [1,2")

    def test_from_yaml_not_dict(self):
        with raises(
            DataSafeHavenConfigError,
            match="Unable to parse Pulumi configuration as a dict.",
        ):
            DSHPulumiConfig.from_yaml("5")

    def test_from_yaml_validation_error(self):
        not_valid = "projects: -3"
        with raises(DataSafeHavenTypeError, match="Pulumi configuration is invalid."):
            DSHPulumiConfig.from_yaml(not_valid)

    def test_upload(self, mocker, pulumi_config, context):
        mock_method = mocker.patch.object(AzureSdk, "upload_blob", return_value=None)
        pulumi_config.upload(context)

        mock_method.assert_called_once_with(
            pulumi_config.to_yaml(),
            DSHPulumiConfig.default_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_from_remote(self, mocker, pulumi_config_yaml, context):
        mock_method = mocker.patch.object(
            AzureSdk, "download_blob", return_value=pulumi_config_yaml
        )
        pulumi_config = DSHPulumiConfig.from_remote(context)

        assert isinstance(pulumi_config, DSHPulumiConfig)
        assert pulumi_config["acmedeployment"]
        assert len(pulumi_config.projects) == 2

        mock_method.assert_called_once_with(
            DSHPulumiConfig.default_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_from_remote_or_create(
        self, mocker, pulumi_config_yaml, context, mock_storage_exists
    ):
        mock_exists = mocker.patch.object(AzureSdk, "blob_exists", return_value=True)
        mock_download = mocker.patch.object(
            AzureSdk, "download_blob", return_value=pulumi_config_yaml
        )
        pulumi_config = DSHPulumiConfig.from_remote_or_create(context, projects={})

        assert isinstance(pulumi_config, DSHPulumiConfig)
        assert pulumi_config["acmedeployment"]
        assert len(pulumi_config.projects) == 2

        mock_exists.assert_called_once_with(
            DSHPulumiConfig.default_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

        mock_download.assert_called_once_with(
            DSHPulumiConfig.default_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

        mock_storage_exists.assert_called_once_with(
            context.storage_account_name,
        )

    def test_from_remote_or_create_create(
        self, mocker, pulumi_config_yaml, context, mock_storage_exists  # noqa: ARG002
    ):
        mock_exists = mocker.patch.object(AzureSdk, "blob_exists", return_value=False)
        pulumi_config = DSHPulumiConfig.from_remote_or_create(
            context, encrypted_key="abc", projects={}
        )

        assert isinstance(pulumi_config, DSHPulumiConfig)
        assert len(pulumi_config.projects) == 0

        mock_exists.assert_called_once_with(
            DSHPulumiConfig.default_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

        mock_storage_exists.assert_called_once_with(
            context.storage_account_name,
        )

    def test_create_or_select_project(self, pulumi_config, pulumi_project):
        assert len(pulumi_config.project_names) == 2
        project = pulumi_config.create_or_select_project("acmedeployment")
        assert len(pulumi_config.project_names) == 2
        assert isinstance(project, DSHPulumiProject)
        assert project == pulumi_project
        project = pulumi_config.create_or_select_project("new_project")
        assert len(pulumi_config.project_names) == 3
        assert isinstance(project, DSHPulumiProject)
        assert project.stack_config == {}
