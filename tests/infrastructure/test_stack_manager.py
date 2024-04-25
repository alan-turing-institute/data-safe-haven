from collections.abc import MutableMapping

from pulumi.automation import ConfigValue, LocalWorkspace, Stack
from pytest import fixture

from data_safe_haven.infrastructure import SHMStackManager
from data_safe_haven.infrastructure.stack_manager import (
    AzureCliSingleton,
    PulumiAccount,
    StackManager,
)


@fixture
def mock_azure_cli_confirm(monkeypatch):
    """Always pass AzureCliSingleton.confirm without attempting login"""
    monkeypatch.setattr(AzureCliSingleton, "confirm", lambda self: None)  # noqa: ARG005


@fixture
def mock_install_plugins(monkeypatch):
    """Skip installing Pulumi plugins"""
    monkeypatch.setattr(
        StackManager, "install_plugins", lambda self: None  # noqa: ARG005
    )


@fixture
def offline_pulumi_account(monkeypatch, mock_azure_cli_confirm):  # noqa: ARG001
    """Overwrite PulumiAccount so that it runs locally"""
    monkeypatch.setattr(PulumiAccount, "env", {})


@fixture
def shm_stack_manager(
    context,
    config_sres,
    pulumi_project,
    mock_azure_cli_confirm,  # noqa: ARG001
    mock_install_plugins,  # noqa: ARG001
    mock_key_vault_key,  # noqa: ARG001
    offline_pulumi_account,  # noqa: ARG001
):
    return SHMStackManager(context, config_sres, pulumi_project)


class TestSHMStackManager:
    def test_constructor(
        self,
        context,
        config_sres,
        pulumi_project,
        mock_azure_cli_confirm,  # noqa: ARG002
        mock_install_plugins,  # noqa: ARG002
    ):
        shm = SHMStackManager(context, config_sres, pulumi_project)
        assert isinstance(shm, SHMStackManager)
        assert isinstance(shm, StackManager)
        assert shm.context == context
        assert shm.cfg == config_sres
        assert shm.pulumi_project == pulumi_project

    def test_stack(self, shm_stack_manager):
        stack = shm_stack_manager.stack
        assert isinstance(stack, Stack)

    def test_stack_config(self, shm_stack_manager):
        stack = shm_stack_manager.stack
        assert stack.name == "shm-acmedeployment"
        assert isinstance(stack.workspace, LocalWorkspace)
        workspace = stack.workspace
        assert (
            workspace.secrets_provider
            == shm_stack_manager.context.pulumi_secrets_provider_url
        )
        assert workspace.env_vars == {}
        config = stack.get_all_config()
        assert config["azure-native:location"].value == "uksouth"
        assert config["data-safe-haven:variable"].value == "5"

    def test_stack_all_config(self, shm_stack_manager):
        config = shm_stack_manager.stack_all_config
        assert isinstance(config, MutableMapping)
        assert isinstance(config["azure-native:location"], ConfigValue)
        assert config["azure-native:location"].value == "uksouth"
        assert config["data-safe-haven:variable"].value == "5"
