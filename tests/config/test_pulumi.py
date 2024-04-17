from pytest import fixture

from data_safe_haven.functions import b64encode
from data_safe_haven.config.pulumi import PulumiStack


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


class TestPulumiStack:
    def test_pulumi_stack(self, pulumi_stack):
        assert pulumi_stack.name == "my_stack"
        assert "encryptedkey: zjhejU2XsOKLo95w9CLD" in pulumi_stack.config
