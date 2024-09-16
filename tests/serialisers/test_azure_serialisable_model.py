from pytest import fixture, raises

from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenTypeError,
)
from data_safe_haven.external import AzureSdk
from data_safe_haven.serialisers import AzureSerialisableModel


class ExampleAzureSerialisableModel(AzureSerialisableModel):
    config_type = "Example"
    default_filename = "file.yaml"
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
    return "\n".join(["string: 'hello'", "integer: 5", "list_of_integers: [1,2,3]"])


class TestAzureSerialisableModel:
    def test_constructor(self, example_config_class):
        assert isinstance(example_config_class, ExampleAzureSerialisableModel)
        assert isinstance(example_config_class, AzureSerialisableModel)
        assert example_config_class.string == "hello"

    def test_remote_yaml_diff(self, mocker, example_config_class, context):
        mocker.patch.object(
            AzureSdk, "download_blob", return_value=example_config_class.to_yaml()
        )
        diff = example_config_class.remote_yaml_diff(context)
        assert not diff
        assert diff == []

    def test_remote_yaml_diff_difference(self, mocker, example_config_class, context):
        mocker.patch.object(
            AzureSdk, "download_blob", return_value=example_config_class.to_yaml()
        )
        example_config_class.integer = 0
        example_config_class.string = "abc"

        diff = example_config_class.remote_yaml_diff(context)

        assert isinstance(diff, list)
        assert diff == [
            "--- remote\n",
            "+++ local\n",
            "@@ -1,6 +1,6 @@\n",
            "-integer: 5\n",
            "+integer: 0\n",
            " list_of_integers:\n",
            " - 1\n",
            " - 2\n",
            " - 3\n",
            "-string: hello\n",
            "+string: abc\n",
        ]

    def test_to_yaml(self, example_config_class):
        yaml = example_config_class.to_yaml()
        assert isinstance(yaml, str)
        assert "string: hello" in yaml
        assert "integer: 5" in yaml
        assert "config_type" not in yaml

    def test_upload(self, mocker, example_config_class, context):
        mock_method = mocker.patch.object(AzureSdk, "upload_blob", return_value=None)
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
        assert example_config_class.string == "hello"
        assert example_config_class.integer == 5
        assert example_config_class.list_of_integers == [1, 2, 3]

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
            DataSafeHavenTypeError,
            match="Example configuration is invalid.",
        ):
            ExampleAzureSerialisableModel.from_yaml(yaml)

    def test_from_remote(self, mocker, context, example_config_yaml):
        mock_method = mocker.patch.object(
            AzureSdk, "download_blob", return_value=example_config_yaml
        )
        example_config = ExampleAzureSerialisableModel.from_remote(context)

        assert isinstance(example_config, ExampleAzureSerialisableModel)
        assert example_config.string == "hello"

        mock_method.assert_called_once_with(
            "file.yaml",
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_from_remote_validation_error(self, mocker, context, example_config_yaml):
        example_config_yaml = example_config_yaml.replace("5", "abc")
        mocker.patch.object(AzureSdk, "download_blob", return_value=example_config_yaml)
        with raises(
            DataSafeHavenTypeError,
            match="'file.yaml' does not contain a valid Example configuration.",
        ):
            ExampleAzureSerialisableModel.from_remote(context)
