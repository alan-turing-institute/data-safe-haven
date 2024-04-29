from unittest.mock import patch

from pytest import fixture, raises

from data_safe_haven.config.azure_serialisable_model import AzureSerialisableModel
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.external import AzureApi


class ExampleAzureSerialisableModel(AzureSerialisableModel):
    config_type = "Example"
    filename = "file.yaml"
    string: str
    integer: int
    list_of_integers: list[int]


@fixture
def example_config_class():
    return ExampleAzureSerialisableModel(
        string="hello", integer=5, list_of_integers=[1, 2, 3]
    )


@fixture
def example_config_yaml():
    return "\n".join(["string: 'abc'", "integer: -3", "list_of_integers: [-1,0,1]"])


class TestAzureSerialisableModel:
    def test_constructor(self, example_config_class):
        assert isinstance(example_config_class, ExampleAzureSerialisableModel)
        assert isinstance(example_config_class, AzureSerialisableModel)
        assert example_config_class.string == "hello"

    def test_to_yaml(self, example_config_class):
        yaml = example_config_class.to_yaml()
        assert isinstance(yaml, str)
        assert "string: hello" in yaml
        assert "integer: 5" in yaml
        assert "config_type" not in yaml

    def test_upload(self, example_config_class, context):
        with patch.object(AzureApi, "upload_blob", return_value=None) as mock_method:
            example_config_class.upload(context)

        mock_method.assert_called_once_with(
            example_config_class.to_yaml(),
            "file.yaml",
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_from_yaml(self, example_config_yaml):
        example_config_class = ExampleAzureSerialisableModel.from_yaml(
            example_config_yaml
        )
        assert isinstance(example_config_class, ExampleAzureSerialisableModel)
        assert isinstance(example_config_class, AzureSerialisableModel)
        assert example_config_class.string == "abc"
        assert example_config_class.integer == -3
        assert example_config_class.list_of_integers == [-1, 0, 1]

    def test_from_yaml_invalid_yaml(self):
        yaml = "\n".join(["string: 'abc'", "integer: -3", "list_of_integers: [-1,0,1"])
        with raises(
            DataSafeHavenConfigError,
            match="Could not parse Example configuration as YAML.",
        ):
            ExampleAzureSerialisableModel.from_yaml(yaml)

    def test_from_yaml_not_dict(self):
        yaml = """42"""
        with raises(
            DataSafeHavenConfigError,
            match="Unable to parse Example configuration as a dict.",
        ):
            ExampleAzureSerialisableModel.from_yaml(yaml)

    def test_from_yaml_validation_error(self):
        yaml = "\n".join(
            ["string: 'abc'", "integer: 'not an integer'", "list_of_integers: [-1,0,1]"]
        )

        with raises(
            DataSafeHavenParameterError,
            match="Could not load Example configuration.",
        ):
            ExampleAzureSerialisableModel.from_yaml(yaml)

    def test_from_remote(self, context, example_config_yaml):
        with patch.object(
            AzureApi, "download_blob", return_value=example_config_yaml
        ) as mock_method:
            example_config = ExampleAzureSerialisableModel.from_remote(context)

        assert isinstance(example_config, ExampleAzureSerialisableModel)
        assert example_config.string == "abc"

        mock_method.assert_called_once_with(
            "file.yaml",
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )
