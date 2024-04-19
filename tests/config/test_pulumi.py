from unittest.mock import patch

from pytest import fixture, raises

from data_safe_haven.config.pulumi import PulumiConfig, PulumiStack
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.external import AzureApi
from data_safe_haven.functions import b64encode


@fixture
def stack_config():
    return """secretsprovider: azurekeyvault://example
encryptedkey: zjhejU2XsOKLo95w9CLD
config:
  azure-native:location: uksouth
"""


@fixture
def stack_config_encoded(stack_config):
    return b64encode(stack_config)


@fixture
def pulumi_stack(stack_config_encoded):
    return PulumiStack(name="my_stack", config=stack_config_encoded)


@fixture
def pulumi_stack2():
    return PulumiStack(
        name="other_stack",
        config=b64encode(
            """secretsprovider: azurekeyvault://example
encryptedkey: B5tHWpqERXgblwRZ7wgu
config:
  azure-native:location: uksouth
"""
        ),
    )


class TestPulumiStack:
    def test_pulumi_stack(self, pulumi_stack):
        assert pulumi_stack.name == "my_stack"
        assert "encryptedkey: zjhejU2XsOKLo95w9CLD" in pulumi_stack.config

    def test_dump(self, pulumi_stack, stack_config_encoded):
        d = pulumi_stack.model_dump()
        assert d.get("name") == "my_stack"
        assert d.get("config") == stack_config_encoded

    def test_eq(self, pulumi_stack):
        assert pulumi_stack == pulumi_stack.model_copy(deep=True)

    def test_not_eq(self, pulumi_stack, pulumi_stack2):
        assert pulumi_stack != pulumi_stack2

    def test_write_config(self, pulumi_stack, context_tmpdir):
        context, tmpdir = context_tmpdir

        pulumi_stack.write_config(context)

        outfile = (
            tmpdir
            / context.shm_name
            / "pulumi"
            / pulumi_stack.name
            / f"Pulumi.{pulumi_stack.name}.yaml"
        )
        assert outfile.exists()

        text = open(outfile).read()
        assert text == pulumi_stack.config


@fixture
def pulumi_config(pulumi_stack, pulumi_stack2):
    return PulumiConfig(stacks=[pulumi_stack, pulumi_stack2])


@fixture
def pulumi_config_yaml():
    return """stacks:
- config: c2VjcmV0c3Byb3ZpZGVyOiBhenVyZWtleXZhdWx0Oi8vZXhhbXBsZQplbmNyeXB0ZWRrZXk6IHpqaGVqVTJYc09LTG85NXc5Q0xECmNvbmZpZzoKICBhenVyZS1uYXRpdmU6bG9jYXRpb246IHVrc291dGgK
  name: my_stack
- config: c2VjcmV0c3Byb3ZpZGVyOiBhenVyZWtleXZhdWx0Oi8vZXhhbXBsZQplbmNyeXB0ZWRrZXk6IEI1dEhXcHFFUlhnYmx3Ulo3d2d1CmNvbmZpZzoKICBhenVyZS1uYXRpdmU6bG9jYXRpb246IHVrc291dGgK
  name: other_stack
"""


class TestPulumiConfig:
    def test_pulumi_config(self, pulumi_stack):
        config = PulumiConfig(stacks=[pulumi_stack])
        assert config.stacks[0].name == "my_stack"

    def test_unique_list(self, pulumi_stack):
        with raises(ValueError, match="All items must be unique."):
            PulumiConfig(stacks=[pulumi_stack, pulumi_stack.model_copy(deep=True)])

    def test_getitem(self, pulumi_config, pulumi_stack, pulumi_stack2):
        assert pulumi_config["my_stack"] == pulumi_stack
        assert pulumi_config["other_stack"] == pulumi_stack2

    def test_getitem_type_error(self, pulumi_config):
        with raises(TypeError, match="'key' must be a string."):
            pulumi_config[0]

    def test_getitem_index_error(self, pulumi_config):
        with raises(IndexError, match="No configuration for Pulumi stack Ringo."):
            pulumi_config["Ringo"]

    def test_delitem(self, pulumi_config):
        assert len(pulumi_config.stacks) == 2
        del pulumi_config["my_stack"]
        assert len(pulumi_config.stacks) == 1

    def test_delitem_value_error(self, pulumi_config):
        with raises(TypeError, match="'key' must be a string."):
            del pulumi_config[-1]

    def test_delitem_index_error(self, pulumi_config):
        with raises(IndexError, match="No configuration for Pulumi stack Ringo."):
            del pulumi_config["Ringo"]

    def test_setitem(self, pulumi_config, pulumi_stack):
        del pulumi_config["my_stack"]
        assert len(pulumi_config.stack_names) == 1
        assert "my_stack" not in pulumi_config.stack_names
        pulumi_config["my_stack"] = pulumi_stack
        assert len(pulumi_config.stack_names) == 2
        assert "my_stack" in pulumi_config.stack_names

    def test_setitem_type_error(self, pulumi_config):
        with raises(TypeError, match="'key' must be a string."):
            pulumi_config[1] = 5

    def test_setitem_value_error(self, pulumi_config):
        with raises(ValueError, match="Stack other_stack already exists."):
            pulumi_config["other_stack"] = 5

    def test_stack_names(self, pulumi_config):
        assert "my_stack" in pulumi_config.stack_names

    def test_to_yaml(self, pulumi_config):
        yaml = pulumi_config.to_yaml()
        assert isinstance(yaml, str)
        assert "stacks:" in yaml
        assert "config: c2VjcmV0" in yaml

    def test_from_yaml(self, pulumi_config_yaml):
        PulumiConfig.from_yaml(pulumi_config_yaml)

    def test_from_yaml_invalid_yaml(self):
        with raises(
            DataSafeHavenConfigError,
            match="Could not parse Pulumi configuration as YAML.",
        ):
            PulumiConfig.from_yaml("a: [1,2")

    def test_from_yaml_not_dict(self):
        with raises(
            DataSafeHavenConfigError,
            match="Unable to parse Pulumi configuration as a dict.",
        ):
            PulumiConfig.from_yaml("5")

    def test_from_yaml_validation_error(self):
        not_valid = "stacks: -3"
        with raises(
            DataSafeHavenParameterError, match="Could not load Pulumi configuration."
        ):
            PulumiConfig.from_yaml(not_valid)

    def test_upload(self, pulumi_config, context):
        with patch.object(AzureApi, "upload_blob", return_value=None) as mock_method:
            pulumi_config.upload(context)

        mock_method.assert_called_once_with(
            pulumi_config.to_yaml(),
            context.pulumi_config_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_from_remote(self, pulumi_config_yaml, context):
        with patch.object(AzureApi, "download_blob", return_value=pulumi_config_yaml) as mock_method:
            pulumi_config = PulumiConfig.from_remote(context)

        assert isinstance(pulumi_config, PulumiConfig)
        assert pulumi_config["my_stack"]
        assert len(pulumi_config.stacks) == 2

        mock_method.assert_called_once_with(
            context.pulumi_config_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )
