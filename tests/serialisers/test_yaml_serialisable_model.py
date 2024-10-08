from pytest import fixture, raises

from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenTypeError,
)
from data_safe_haven.serialisers import YAMLSerialisableModel


class ExampleYAMLSerialisableModel(YAMLSerialisableModel):
    config_type = "Example"
    string: str
    integer: int
    list_of_integers: list[int]


@fixture
def example_config_class():
    return ExampleYAMLSerialisableModel(
        string="hello", integer=5, list_of_integers=[1, 2, 3]
    )


@fixture
def example_config_yaml():
    return "\n".join(["string: 'hello'", "integer: 5", "list_of_integers: [1,2,3]"])


class TestYAMLSerialisableModel:
    def test_constructor(self, example_config_class):
        assert isinstance(example_config_class, ExampleYAMLSerialisableModel)
        assert isinstance(example_config_class, YAMLSerialisableModel)
        assert example_config_class.string == "hello"

    def test_from_filepath(self, tmp_path, example_config_yaml):
        filepath = tmp_path / "test.yaml"
        filepath.write_text(example_config_yaml)
        example_config_class = ExampleYAMLSerialisableModel.from_filepath(filepath)
        assert isinstance(example_config_class, ExampleYAMLSerialisableModel)
        assert isinstance(example_config_class, YAMLSerialisableModel)
        assert example_config_class.string == "hello"
        assert example_config_class.integer == 5
        assert example_config_class.list_of_integers == [1, 2, 3]

    def test_from_yaml(self, example_config_yaml):
        example_config_class = ExampleYAMLSerialisableModel.from_yaml(
            example_config_yaml
        )
        assert isinstance(example_config_class, ExampleYAMLSerialisableModel)
        assert isinstance(example_config_class, YAMLSerialisableModel)
        assert example_config_class.string == "hello"
        assert example_config_class.integer == 5
        assert example_config_class.list_of_integers == [1, 2, 3]

    def test_from_yaml_invalid_yaml(self):
        yaml = "\n".join(["string: 'abc'", "integer: -3", "list_of_integers: [-1,0,1"])
        with raises(
            DataSafeHavenConfigError,
            match="Could not parse Example configuration as YAML.",
        ):
            ExampleYAMLSerialisableModel.from_yaml(yaml)

    def test_from_yaml_not_dict(self):
        yaml = """42"""
        with raises(
            DataSafeHavenConfigError,
            match="Unable to parse Example configuration as a dict.",
        ):
            ExampleYAMLSerialisableModel.from_yaml(yaml)

    def test_from_yaml_validation_errors(self, caplog):
        yaml = "\n".join(
            [
                "string: 'abc'",
                "integer: 'not an integer'",
                "list_of_integers: [-1,0,z,1]",
            ]
        )
        with raises(
            DataSafeHavenTypeError,
            match="Example configuration is invalid.",
        ):
            ExampleYAMLSerialisableModel.from_yaml(yaml)
        assert "Input should be a valid integer" in caplog.text
        assert "Original input: not an integer" in caplog.text
        assert "unable to parse string as an integer" in caplog.text
        assert "list_of_integers.2" in caplog.text
        assert "Original input: z" in caplog.text

    def test_to_filepath(self, tmp_path, example_config_class):
        filepath = tmp_path / "test.yaml"
        example_config_class.to_filepath(filepath)
        contents = filepath.read_text().split("\n")
        assert "string: hello" in contents
        assert "integer: 5" in contents
        assert "list_of_integers:" in contents
        assert "- 1" in contents
        assert "- 2" in contents
        assert "- 3" in contents

    def test_to_yaml(self, example_config_class):
        yaml = example_config_class.to_yaml()
        assert isinstance(yaml, str)
        assert "string: hello" in yaml
        assert "integer: 5" in yaml
        assert "config_type" not in yaml

    def test_yaml_diff(self, example_config_class):
        other = example_config_class.model_copy(deep=True)
        diff = example_config_class.yaml_diff(other)
        assert not diff
        assert diff == []

    def test_yaml_diff_difference(self, example_config_class):
        other = example_config_class.model_copy(deep=True)
        other.integer = 3
        other.string = "abc"
        diff = example_config_class.yaml_diff(other)
        assert isinstance(diff, list)
        assert diff == [
            "--- other\n",
            "+++ self\n",
            "@@ -1,6 +1,6 @@\n",
            "-integer: 3\n",
            "+integer: 5\n",
            " list_of_integers:\n",
            " - 1\n",
            " - 2\n",
            " - 3\n",
            "-string: abc\n",
            "+string: hello\n",
        ]
